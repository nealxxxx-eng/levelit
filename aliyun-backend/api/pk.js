/**
 * PK Challenge CRUD handlers
 * 路由由 server.js 分派，所有接口都需要 Bearer token 认证。
 *
 * 存储：levelit-pk.json（与 levelit-users.json 同目录）
 * 并发安全：使用与 auth 相同的 Promise 串行锁模式
 */
import crypto from "node:crypto";
import { promises as fs } from "node:fs";

const PK_DB_FILE = process.env.LEVELIT_PK_DB_FILE || "./levelit-pk.json";

// ── 存储锁
let pkWriteLock = Promise.resolve();
function withPKLock(fn) {
  const next = pkWriteLock.then(fn);
  pkWriteLock = next.catch(() => {});
  return next;
}

async function readDB() {
  try {
    const raw = await fs.readFile(PK_DB_FILE, "utf8");
    if (!raw.trim()) return { challenges: [] };
    return JSON.parse(raw);
  } catch (e) {
    if (e.code === "ENOENT") return { challenges: [] };
    throw e;
  }
}

async function writeDB(db) {
  await fs.writeFile(PK_DB_FILE, JSON.stringify(db, null, 2));
}

// ── 辅助
function json(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
  });
  res.end(data);
}

async function readBody(req) {
  return new Promise((resolve, reject) => {
    let buf = "";
    req.on("data", (c) => {
      buf += c;
      if (buf.length > 2 * 1024 * 1024) req.destroy(new Error("too large"));
    });
    req.on("end", () => {
      try { resolve(buf ? JSON.parse(buf) : {}); }
      catch { reject(new Error("invalid json")); }
    });
    req.on("error", reject);
  });
}

// 只暴露给客户端的字段（不含 deviceToken）
function publicChallenge(c) {
  return {
    id:                  c.id,
    inviteCode:          c.inviteCode,
    type:                c.type,
    status:              c.status,
    title:               c.title,
    challengerId:        c.challengerId,
    challengerName:      c.challengerName,
    challengerCode:      c.challengerCode,
    challengerProgress:  c.challengerProgress,
    opponentId:          c.opponentId,
    opponentName:        c.opponentName,
    opponentCode:        c.opponentCode,
    opponentProgress:    c.opponentProgress,
    targetCalories:      c.targetCalories,
    durationDays:        c.durationDays,
    expiresAt:           c.expiresAt,
    createdAt:           c.createdAt,
    acceptedAt:          c.acceptedAt,
    completedAt:         c.completedAt,
    note:                c.note,
  };
}

// ── 主函数：接收已验证的 userId，处理请求
export async function handlePKRoutes(req, res, url, userId, sendPush) {
  const segments = url.pathname.replace(/\/+$/, "").split("/");
  // /api/pk/challenges[/:id][/progress|device-token]
  // /api/pk/claim

  // POST /api/pk/claim
  if (req.method === "POST" && url.pathname === "/api/pk/claim") {
    return handleClaim(req, res, userId, sendPush);
  }

  const challengesBase = segments[3] === "challenges";
  if (!challengesBase) return json(res, 404, { error: "not found" });

  const id      = segments[4];
  const subPath = segments[5]; // "progress" | "device-token" | undefined

  if (!id) {
    // /api/pk/challenges
    if (req.method === "GET")  return handleList(req, res, userId);
    if (req.method === "POST") return handleCreate(req, res, userId);
    return json(res, 405, { error: "method not allowed" });
  }

  if (subPath === "progress") {
    if (req.method === "PUT") return handleUpdateProgress(req, res, id, userId, sendPush);
    return json(res, 405, { error: "method not allowed" });
  }

  if (subPath === "device-token") {
    if (req.method === "PUT") return handleRegisterDeviceToken(req, res, id, userId);
    return json(res, 405, { error: "method not allowed" });
  }

  // /api/pk/challenges/:id
  if (req.method === "GET")    return handleGet(req, res, id, userId);
  if (req.method === "PUT")    return handleUpdate(req, res, id, userId);
  if (req.method === "DELETE") return handleDelete(req, res, id, userId);
  return json(res, 405, { error: "method not allowed" });
}

// ── 创建挑战
async function handleCreate(req, res, userId) {
  const body = await readBody(req);
  const { type, title, challengerName, challengerCode, opponentName,
          targetCalories, durationDays, note, expiresInHours } = body;

  if (!type || !title || !challengerName || !challengerCode || !targetCalories) {
    return json(res, 400, { error: "type, title, challengerName, challengerCode, targetCalories required" });
  }

  await withPKLock(async () => {
    const db  = await readDB();
    const now = new Date().toISOString();
    const id  = crypto.randomUUID();
    const ttl = Math.max(1, Math.min(168, Number(expiresInHours) || 48)); // 1h ~ 7d

    const challenge = {
      id,
      inviteCode:          `${String(challengerCode).toUpperCase()}-${id.slice(0, 6).toUpperCase()}`,
      type,
      status:              "invited",
      title,
      challengerId:        userId,
      challengerName,
      challengerCode:      String(challengerCode).toUpperCase(),
      challengerProgress:  0,
      challengerDeviceToken: null,
      opponentId:          null,
      opponentName:        opponentName || null,
      opponentCode:        null,
      opponentProgress:    0,
      opponentDeviceToken: null,
      targetCalories:      Math.max(1, Number(targetCalories)),
      durationDays:        Math.max(1, Number(durationDays) || 1),
      expiresAt:           new Date(Date.now() + ttl * 3600 * 1000).toISOString(),
      createdAt:           now,
      acceptedAt:          null,
      completedAt:         null,
      note:                note || null,
    };

    db.challenges.push(challenge);
    await writeDB(db);
    json(res, 201, publicChallenge(challenge));
  });
}

// ── 列出我参与的挑战
async function handleList(req, res, userId) {
  const db   = await readDB();
  const mine = db.challenges.filter(
    (c) => c.challengerId === userId || c.opponentId === userId
  );
  json(res, 200, mine.map(publicChallenge));
}

// ── 获取单个挑战
async function handleGet(req, res, id, userId) {
  const db = await readDB();
  const c  = db.challenges.find((c) => c.id === id);
  if (!c) return json(res, 404, { error: "not found" });
  if (c.challengerId !== userId && c.opponentId !== userId)
    return json(res, 403, { error: "forbidden" });
  json(res, 200, publicChallenge(c));
}

// ── 编辑挑战（仅 invited 状态 + 发起方）
async function handleUpdate(req, res, id, userId) {
  const body = await readBody(req);
  await withPKLock(async () => {
    const db = await readDB();
    const c  = db.challenges.find((c) => c.id === id);
    if (!c) return json(res, 404, { error: "not found" });
    if (c.challengerId !== userId) return json(res, 403, { error: "only challenger can edit" });

    // 撤回
    if (body.status === "cancelled") {
      if (c.status !== "invited") return json(res, 409, { error: "can only cancel invited challenges" });
      c.status = "cancelled";
      await writeDB(db);
      return json(res, 200, publicChallenge(c));
    }

    if (c.status !== "invited") return json(res, 409, { error: "cannot edit after accepted" });
    if (body.title)          c.title          = body.title;
    if (body.targetCalories) c.targetCalories = Math.max(1, Number(body.targetCalories));
    if (body.durationDays)   c.durationDays   = Math.max(1, Number(body.durationDays));
    if (body.expiresAt)      c.expiresAt      = body.expiresAt;
    if (body.note !== undefined) c.note       = body.note || null;

    await writeDB(db);
    json(res, 200, publicChallenge(c));
  });
}

// ── 删除挑战（仅终态，仅发起方）
async function handleDelete(req, res, id, userId) {
  await withPKLock(async () => {
    const db  = await readDB();
    const idx = db.challenges.findIndex((c) => c.id === id);
    if (idx === -1) return json(res, 404, { error: "not found" });
    if (db.challenges[idx].challengerId !== userId) return json(res, 403, { error: "forbidden" });
    db.challenges.splice(idx, 1);
    await writeDB(db);
    json(res, 200, { ok: true });
  });
}

// ── 认领挑战
async function handleClaim(req, res, userId, sendPush) {
  const body        = await readBody(req);
  const inviteCode  = String(body.inviteCode || "").trim().toUpperCase();
  const opponentName = String(body.opponentName || "").trim() || "对手";
  const opponentCode = String(body.opponentCode || "").trim().toUpperCase();

  if (!inviteCode) return json(res, 400, { error: "inviteCode required" });

  await withPKLock(async () => {
    const db = await readDB();
    const c  = db.challenges.find((c) => c.inviteCode === inviteCode && c.status === "invited");
    if (!c) return json(res, 404, { error: "invite code not found or already claimed" });
    if (c.challengerId === userId) return json(res, 409, { error: "cannot claim your own challenge" });
    if (new Date(c.expiresAt) < new Date()) {
      c.status = "expired";
      await writeDB(db);
      return json(res, 410, { error: "invite has expired" });
    }

    c.opponentId   = userId;
    c.opponentName = opponentName;
    c.opponentCode = opponentCode || null;
    c.status       = "accepted";
    c.acceptedAt   = new Date().toISOString();
    await writeDB(db);

    // 通知发起方
    if (c.challengerDeviceToken) {
      sendPush(c.challengerDeviceToken, {
        title: "挑战已被认领！",
        body:  `${opponentName} 接受了你的挑战「${c.title}」，开始磨平吧！`,
        data:  { challengeId: c.id, type: "challenge_accepted" },
      }).catch(() => {});
    }

    json(res, 200, publicChallenge(c));
  });
}

// ── 更新进度
async function handleUpdateProgress(req, res, id, userId, sendPush) {
  const body     = await readBody(req);
  const progress = Math.max(0, Number(body.progress) || 0);

  await withPKLock(async () => {
    const db = await readDB();
    const c  = db.challenges.find((c) => c.id === id);
    if (!c) return json(res, 404, { error: "not found" });
    if (c.status !== "accepted") return json(res, 409, { error: "challenge not active" });

    const isChallenger = c.challengerId === userId;
    const isOpponent   = c.opponentId   === userId;
    if (!isChallenger && !isOpponent) return json(res, 403, { error: "forbidden" });

    if (isChallenger) c.challengerProgress = progress;
    else              c.opponentProgress   = progress;

    // 检查是否完成
    if (c.challengerProgress >= c.targetCalories || c.opponentProgress >= c.targetCalories) {
      c.status      = "completed";
      c.completedAt = new Date().toISOString();

      const winnerName  = c.challengerProgress >= c.targetCalories ? c.challengerName : c.opponentName;
      const notifyToken = isChallenger ? c.opponentDeviceToken : c.challengerDeviceToken;
      if (notifyToken) {
        sendPush(notifyToken, {
          title: "对手完成了！",
          body:  `${winnerName} 已完成挑战「${c.title}」！`,
          data:  { challengeId: c.id, type: "challenge_completed" },
        }).catch(() => {});
      }
    }

    await writeDB(db);
    json(res, 200, publicChallenge(c));
  });
}

// ── 注册 APNs device token
async function handleRegisterDeviceToken(req, res, id, userId) {
  const body        = await readBody(req);
  const deviceToken = String(body.deviceToken || "").trim();
  if (!deviceToken) return json(res, 400, { error: "deviceToken required" });

  await withPKLock(async () => {
    const db = await readDB();
    const c  = db.challenges.find((c) => c.id === id);
    if (!c) return json(res, 404, { error: "not found" });

    if      (c.challengerId === userId) c.challengerDeviceToken = deviceToken;
    else if (c.opponentId   === userId) c.opponentDeviceToken   = deviceToken;
    else return json(res, 403, { error: "forbidden" });

    await writeDB(db);
    json(res, 200, { ok: true });
  });
}
