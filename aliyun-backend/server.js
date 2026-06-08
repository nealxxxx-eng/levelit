import crypto from "node:crypto";
import { promises as fs } from "node:fs";
import http from "node:http";
import { handlePKRoutes } from "./api/pk.js";
import { sendPushNotification } from "./api/apns.js";

const PORT = Number(process.env.PORT || 3000);
const DB_FILE = process.env.LEVELIT_DB_FILE || "./levelit-users.json";
const AUTH_SECRET = process.env.LEVELIT_AUTH_SECRET || "replace-this-before-deploy";
const TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60; // 30 天

// Bug #5：默认 secret 未替换时拒绝启动（线上环境必须通过环境变量注入）
if (AUTH_SECRET === "replace-this-before-deploy") {
  if (process.env.NODE_ENV === "production") {
    console.error("FATAL: LEVELIT_AUTH_SECRET is not set. Refusing to start in production.");
    process.exit(1);
  } else {
    console.warn("WARNING: Using default AUTH_SECRET. Set LEVELIT_AUTH_SECRET before deploying.");
  }
}

// 串行化所有 DB 写操作，防止并发竞态导致重复账号或数据丢失
let dbWriteLock = Promise.resolve();
function withDBLock(fn) {
  const next = dbWriteLock.then(fn);
  dbWriteLock = next.catch(() => {});
  return next;
}

async function readDB() {
  try {
    const raw = await fs.readFile(DB_FILE, "utf8");
    if (!raw.trim()) return { users: [] };
    return JSON.parse(raw);
  } catch (error) {
    if (error.code === "ENOENT") return { users: [] };
    throw error;
  }
}

async function writeDB(db) {
  await fs.writeFile(DB_FILE, JSON.stringify(db, null, 2));
}

function json(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store"
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", chunk => {
      body += chunk;
      if (body.length > 1024 * 1024) {
        req.destroy(new Error("request too large"));
      }
    });
    req.on("end", () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        reject(new Error("invalid json"));
      }
    });
    req.on("error", reject);
  });
}

function normalizeIdentifier(identifier) {
  return String(identifier || "").trim().toLowerCase();
}

function hashPassword(password, salt = crypto.randomBytes(16).toString("hex")) {
  const hash = crypto.pbkdf2Sync(String(password), salt, 120000, 32, "sha256").toString("hex");
  return `${salt}:${hash}`;
}

function verifyPassword(password, stored) {
  const [salt, expected] = String(stored || "").split(":");
  if (!salt || !expected) return false;
  const actual = hashPassword(password, salt).split(":")[1];
  // 长度不同时 timingSafeEqual 会抛 RangeError（DB 数据损坏场景），必须提前守卫
  if (actual.length !== expected.length) return false;
  return crypto.timingSafeEqual(Buffer.from(actual, "hex"), Buffer.from(expected, "hex"));
}

function signToken(userId) {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    sub: userId,
    iat: now,
    exp: now + TOKEN_TTL_SECONDS,
    nonce: crypto.randomUUID()
  };
  const encoded = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = crypto.createHmac("sha256", AUTH_SECRET).update(encoded).digest("base64url");
  return `${encoded}.${signature}`;
}

function verifyToken(token) {
  const [encoded, signature] = String(token || "").split(".");
  if (!encoded || !signature) return null;
  const expected = crypto.createHmac("sha256", AUTH_SECRET).update(encoded).digest("base64url");
  // 长度不同时 timingSafeEqual 会抛 RangeError，必须提前守卫
  if (signature.length !== expected.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
  try {
    const payload = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
    // Bug #4：校验过期时间
    if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

function bearerToken(req) {
  const value = req.headers.authorization || "";
  return value.startsWith("Bearer ") ? value.slice("Bearer ".length) : "";
}

function publicUser(user) {
  return {
    userId: user.id,
    identifier: user.identifier,
    profile: user.profile
  };
}

async function requireUser(req, res) {
  const claims = verifyToken(bearerToken(req));
  if (!claims?.sub) {
    json(res, 401, { error: "unauthorized" });
    return null;
  }

  const db = await readDB();
  const user = db.users.find(item => item.id === claims.sub);
  if (!user) {
    json(res, 401, { error: "user not found" });
    return null;
  }

  return { db, user };
}

async function handleRegister(req, res) {
  const body = await readBody(req);
  const identifier = normalizeIdentifier(body.identifier);
  const password = String(body.password || "");
  const profile = body.profile;

  if (!identifier || password.length < 6 || !profile) {
    json(res, 400, { error: "identifier, password and profile are required" });
    return;
  }

  await withDBLock(async () => {
    const db = await readDB();
    if (db.users.some(user => user.identifier === identifier)) {
      json(res, 409, { error: "account already exists" });
      return;
    }

    const user = {
      id: crypto.randomUUID(),
      identifier,
      passwordHash: hashPassword(password),
      profile,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    db.users.push(user);
    await writeDB(db);

    json(res, 201, {
      token: signToken(user.id),
      userId: user.id,
      profile: user.profile
    });
  });
}

async function handleLogin(req, res) {
  const body = await readBody(req);
  const identifier = normalizeIdentifier(body.identifier);
  const password = String(body.password || "");
  const db = await readDB();
  const user = db.users.find(item => item.identifier === identifier);

  if (!user || !verifyPassword(password, user.passwordHash)) {
    json(res, 401, { error: "invalid credentials" });
    return;
  }

  json(res, 200, {
    token: signToken(user.id),
    userId: user.id,
    profile: user.profile
  });
}

async function handleMe(req, res) {
  const context = await requireUser(req, res);
  if (!context) return;
  json(res, 200, publicUser(context.user));
}

async function handleProfileUpdate(req, res) {
  const body = await readBody(req);
  if (!body.profile) {
    json(res, 400, { error: "profile is required" });
    return;
  }

  const claims = verifyToken(bearerToken(req));
  if (!claims?.sub) {
    json(res, 401, { error: "unauthorized" });
    return;
  }

  await withDBLock(async () => {
    const db = await readDB();
    const user = db.users.find(item => item.id === claims.sub);
    if (!user) {
      json(res, 401, { error: "user not found" });
      return;
    }

    user.profile = body.profile;
    user.updatedAt = new Date().toISOString();
    await writeDB(db);
    json(res, 200, publicUser(user));
  });
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (req.method === "POST" && url.pathname === "/api/auth/register") return handleRegister(req, res);
    if (req.method === "POST" && url.pathname === "/api/auth/login") return handleLogin(req, res);
    if (req.method === "GET" && url.pathname === "/api/auth/me") return handleMe(req, res);
    if (req.method === "PUT" && url.pathname === "/api/auth/profile") return handleProfileUpdate(req, res);
    if (req.method === "GET" && url.pathname === "/health") return json(res, 200, { ok: true });

    // PK 挑战接口 — 所有 /api/pk/* 路由都需要 Bearer token
    if (url.pathname.startsWith("/api/pk/")) {
      const claims = verifyToken(bearerToken(req));
      if (!claims?.sub) return json(res, 401, { error: "unauthorized" });
      return handlePKRoutes(req, res, url, claims.sub, sendPushNotification);
    }

    json(res, 404, { error: "not found" });
  } catch (error) {
    json(res, 500, { error: error.message || "internal server error" });
  }
});

server.listen(PORT, () => {
  console.log(`LevelIt auth backend listening on :${PORT}`);
});
