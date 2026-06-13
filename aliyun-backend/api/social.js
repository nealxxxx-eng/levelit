/**
 * 好友关系 API。路由由 server.js 分派，所有接口都已通过 token 校验，userId 注入。
 *
 * 存储：social.json —— { links: [{ id, fromUserId, toUserId, status, createdAt, updatedAt }] }
 *   status: "pending"（已发请求待对方处理）| "accepted"（已是好友）
 *   两人之间最多保留一条记录；拒绝/删除直接移除记录。
 */
import crypto from "node:crypto";
import { promises as fs } from "node:fs";
import { findUserByUsername, findUserById, publicUserInfo } from "./users-store.js";

const SOCIAL_DB_FILE = process.env.LEVELIT_SOCIAL_DB_FILE || "./levelit-social.json";

let writeLock = Promise.resolve();
function withLock(fn) {
  const next = writeLock.then(fn);
  writeLock = next.catch(() => {});
  return next;
}

async function readDB() {
  try {
    const raw = await fs.readFile(SOCIAL_DB_FILE, "utf8");
    if (!raw.trim()) return { links: [] };
    return JSON.parse(raw);
  } catch (e) {
    if (e.code === "ENOENT") return { links: [] };
    throw e;
  }
}
async function writeDB(db) {
  await fs.writeFile(SOCIAL_DB_FILE, JSON.stringify(db, null, 2));
}

function json(res, status, body) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify(body));
}
async function readBody(req) {
  return new Promise((resolve, reject) => {
    let b = "";
    req.on("data", c => { b += c; if (b.length > 256 * 1024) req.destroy(new Error("too large")); });
    req.on("end", () => { try { resolve(b ? JSON.parse(b) : {}); } catch { reject(new Error("invalid json")); } });
    req.on("error", reject);
  });
}

function linkBetween(db, x, y) {
  return db.links.find(l =>
    (l.fromUserId === x && l.toUserId === y) ||
    (l.fromUserId === y && l.toUserId === x));
}

// ── 主分派
export async function handleSocialRoutes(req, res, url, userId) {
  const seg = url.pathname.replace(/\/+$/, "").split("/"); // /api/friends[/requests[/:id/accept|reject]] | /api/friends/:username

  // /api/friends/request  (POST)  发好友请求
  if (req.method === "POST" && url.pathname === "/api/friends/request") {
    return sendRequest(req, res, userId);
  }
  // /api/friends/requests (GET) 待处理请求
  if (req.method === "GET" && url.pathname === "/api/friends/requests") {
    return listRequests(req, res, userId);
  }
  // /api/friends/requests/:id/accept | reject (POST)
  if (req.method === "POST" && seg[3] === "requests" && seg[5]) {
    const id = seg[4], action = seg[5];
    if (action === "accept") return acceptRequest(req, res, userId, id);
    if (action === "reject") return rejectRequest(req, res, userId, id);
    return json(res, 404, { error: "not found" });
  }
  // /api/friends (GET) 好友列表
  if (req.method === "GET" && url.pathname === "/api/friends") {
    return listFriends(req, res, userId);
  }
  // /api/friends/:username (DELETE) 删好友
  if (req.method === "DELETE" && seg[3] && seg.length === 4) {
    return removeFriend(req, res, userId, decodeURIComponent(seg[3]));
  }
  return json(res, 404, { error: "not found" });
}

// ── 发好友请求
async function sendRequest(req, res, userId) {
  const body = await readBody(req);
  const target = await findUserByUsername(body.username);
  if (!target) return json(res, 404, { error: "用户不存在" });
  if (target.id === userId) return json(res, 400, { error: "不能加自己为好友" });

  await withLock(async () => {
    const db = await readDB();
    const existing = linkBetween(db, userId, target.id);
    if (existing) {
      if (existing.status === "accepted") return json(res, 409, { error: "你们已经是好友" });
      // 已存在 pending：若是对方先发给我，则直接互相接受
      if (existing.toUserId === userId) {
        existing.status = "accepted";
        existing.updatedAt = new Date().toISOString();
        await writeDB(db);
        return json(res, 200, { status: "accepted" });
      }
      return json(res, 409, { error: "请求已发送，等待对方确认" });
    }
    db.links.push({
      id: crypto.randomUUID(),
      fromUserId: userId,
      toUserId: target.id,
      status: "pending",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    await writeDB(db);
    json(res, 201, { status: "pending" });
  });
}

// ── 待处理请求（收到的 + 发出的）
async function listRequests(req, res, userId) {
  const db = await readDB();
  const pending = db.links.filter(l => l.status === "pending");
  const incoming = [];
  const outgoing = [];
  for (const l of pending) {
    if (l.toUserId === userId) {
      incoming.push({ id: l.id, user: publicUserInfo(await findUserById(l.fromUserId)), createdAt: l.createdAt });
    } else if (l.fromUserId === userId) {
      outgoing.push({ id: l.id, user: publicUserInfo(await findUserById(l.toUserId)), createdAt: l.createdAt });
    }
  }
  json(res, 200, { incoming, outgoing });
}

// ── 接受请求（仅被请求方）
async function acceptRequest(req, res, userId, id) {
  await withLock(async () => {
    const db = await readDB();
    const l = db.links.find(x => x.id === id);
    if (!l || l.status !== "pending") return json(res, 404, { error: "请求不存在" });
    if (l.toUserId !== userId) return json(res, 403, { error: "无权操作" });
    l.status = "accepted";
    l.updatedAt = new Date().toISOString();
    await writeDB(db);
    json(res, 200, { status: "accepted" });
  });
}

// ── 拒绝请求（仅被请求方）：直接移除
async function rejectRequest(req, res, userId, id) {
  await withLock(async () => {
    const db = await readDB();
    const idx = db.links.findIndex(x => x.id === id);
    if (idx === -1 || db.links[idx].status !== "pending") return json(res, 404, { error: "请求不存在" });
    if (db.links[idx].toUserId !== userId) return json(res, 403, { error: "无权操作" });
    db.links.splice(idx, 1);
    await writeDB(db);
    json(res, 200, { ok: true });
  });
}

// ── 好友列表
async function listFriends(req, res, userId) {
  const db = await readDB();
  const accepted = db.links.filter(l => l.status === "accepted" &&
    (l.fromUserId === userId || l.toUserId === userId));
  const friends = [];
  for (const l of accepted) {
    const otherId = l.fromUserId === userId ? l.toUserId : l.fromUserId;
    const info = publicUserInfo(await findUserById(otherId));
    if (info) friends.push(info);
  }
  json(res, 200, { friends });
}

// ── 删好友
async function removeFriend(req, res, userId, username) {
  const target = await findUserByUsername(username);
  if (!target) return json(res, 404, { error: "用户不存在" });
  await withLock(async () => {
    const db = await readDB();
    const idx = db.links.findIndex(l =>
      l.status === "accepted" &&
      ((l.fromUserId === userId && l.toUserId === target.id) ||
       (l.fromUserId === target.id && l.toUserId === userId)));
    if (idx === -1) return json(res, 404, { error: "你们不是好友" });
    db.links.splice(idx, 1);
    await writeDB(db);
    json(res, 200, { ok: true });
  });
}

/** 判断两人是否好友（供 pk.js 校验"只能挑战好友"等场景，可选用） */
export async function areFriends(userA, userB) {
  const db = await readDB();
  return db.links.some(l => l.status === "accepted" &&
    ((l.fromUserId === userA && l.toUserId === userB) ||
     (l.fromUserId === userB && l.toUserId === userA)));
}
