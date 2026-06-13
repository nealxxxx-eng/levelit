/**
 * PK Challenge CRUD handlers
 * 路由由 server.js 分派，所有接口都需要 Bearer token 认证。
 *
 * 存储：levelit-pk.json（与 levelit-users.json 同目录）
 * 并发安全：使用与 auth 相同的 Promise 串行锁模式
 */
import crypto from "node:crypto";
import { promises as fs } from "node:fs";
import { findUserByUsername, findUserById, getPublicUserMap } from "./users-store.js";

const PK_DB_FILE = process.env.LEVELIT_PK_DB_FILE || "./levelit-pk.json";

// 防滥用：每人最多同时挂这么多条「公开、待认领」的发榜挑战
const MAX_OPEN_PUBLIC_PER_USER = 5;

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

// 只暴露给客户端的字段。
// 不含 deviceToken；也不含内部 challengerId/opponentId（服务端用户 UUID），
// 避免把内部标识泄露给挑战的另一方。当事人身份由 token 决定，无需返回。
function publicChallenge(c, viewerId = null) {
  // 相对观察者的角色与待办，不暴露内部 userId
  const myRole = viewerId && c.challengerId === viewerId ? "challenger"
               : viewerId && c.opponentId === viewerId ? "opponent"
               : null;
  // 定向挑战（指定了好友）等待该好友接受
  const awaitingMyAcceptance = viewerId != null && c.status === "invited" &&
                               c.opponentId === viewerId;
  return {
    id:                  c.id,
    inviteCode:          c.inviteCode,
    type:                c.type,
    status:              c.status,
    title:               c.title,
    visibility:          c.visibility || "private",
    isDirected:          c.opponentId != null && c.status === "invited",
    myRole,
    awaitingMyAcceptance,
    challengerName:      c.challengerName,
    challengerCode:      c.challengerCode,
    challengerUsername:  c.challengerUsername || null,
    challengerProgress:  c.challengerProgress,
    opponentName:        c.opponentName,
    opponentCode:        c.opponentCode,
    opponentUsername:    c.opponentUsername || null,
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

  // GET /api/pk/board — 公开发榜广场
  if (req.method === "GET" && url.pathname === "/api/pk/board") {
    return handleBoard(req, res, url, userId);
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

  if (subPath === "accept") {
    if (req.method === "PUT") return handleAcceptDirected(req, res, id, userId, sendPush);
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
          targetCalories, durationDays, note, expiresInHours,
          opponentUsername, visibility } = body;

  if (!type || !title || !challengerName || !challengerCode || !targetCalories) {
    return json(res, 400, { error: "type, title, challengerName, challengerCode, targetCalories required" });
  }
  // #10：拒绝非数字 targetCalories（"abc" 能绕过上面的 !targetCalories，导致存成 NaN）
  const targetNum = Number(targetCalories);
  if (!Number.isFinite(targetNum) || targetNum <= 0) {
    return json(res, 400, { error: "targetCalories must be a positive number" });
  }

  // 定向好友挑战：解析 opponentUsername → 该好友
  let directedOpponent = null;
  if (opponentUsername) {
    directedOpponent = await findUserByUsername(opponentUsername);
    if (!directedOpponent) return json(res, 404, { error: "对手用户名不存在" });
    if (directedOpponent.id === userId) return json(res, 400, { error: "不能挑战自己" });
  }
  const me = await findUserById(userId);
  const vis = visibility === "public" ? "public" : "private";

  await withPKLock(async () => {
    const db  = await readDB();

    // 防滥用：公开挑战数量上限
    if (vis === "public") {
      const openPublic = db.challenges.filter(
        (c) => c.challengerId === userId && c.visibility === "public" && c.status === "invited"
      ).length;
      if (openPublic >= MAX_OPEN_PUBLIC_PER_USER) {
        return json(res, 429, { error: `最多同时发布 ${MAX_OPEN_PUBLIC_PER_USER} 条公开挑战，请先撤回一些` });
      }
    }

    const now = new Date().toISOString();
    const id  = crypto.randomUUID();
    const ttl = Math.max(1, Math.min(168, Number(expiresInHours) || 48)); // 1h ~ 7d

    const challenge = {
      id,
      inviteCode:          `${String(challengerCode).toUpperCase()}-${id.slice(0, 6).toUpperCase()}`,
      type,
      status:              "invited",
      visibility:          vis,
      title,
      challengerId:        userId,
      challengerName,
      challengerCode:      String(challengerCode).toUpperCase(),
      challengerUsername:  me?.username || null,
      challengerProgress:  0,
      challengerDeviceToken: null,
      // 定向挑战：预置 opponentId，对方在列表里即可见、直接 accept；非定向为 null（走邀请码/广场认领）
      opponentId:          directedOpponent ? directedOpponent.id : null,
      opponentName:        directedOpponent ? (directedOpponent.profile?.displayName || directedOpponent.username) : (opponentName || null),
      opponentCode:        null,
      opponentUsername:    directedOpponent ? directedOpponent.username : null,
      opponentProgress:    0,
      opponentDeviceToken: null,
      targetCalories:      Math.max(1, Math.round(targetNum)),
      durationDays:        Math.max(1, Number(durationDays) || 1),
      expiresAt:           new Date(Date.now() + ttl * 3600 * 1000).toISOString(),
      createdAt:           now,
      acceptedAt:          null,
      completedAt:         null,
      note:                note || null,
    };

    db.challenges.push(challenge);
    await writeDB(db);
    json(res, 201, publicChallenge(challenge, userId));
  });
}

// ── 列出我参与的挑战
async function handleList(req, res, userId) {
  const db   = await readDB();
  const mine = db.challenges.filter(
    (c) => c.challengerId === userId || c.opponentId === userId
  );
  json(res, 200, mine.map((c) => publicChallenge(c, userId)));
}

// ── 发榜广场：公开、待认领、未过期、非自己发起、未定向给特定人
async function handleBoard(req, res, url, userId) {
  const limit  = Math.max(1, Math.min(50, Number(url.searchParams.get("limit")) || 20));
  const offset = Math.max(0, Number(url.searchParams.get("offset")) || 0);
  const now = Date.now();

  const db = await readDB();
  const open = db.challenges
    .filter((c) =>
      c.visibility === "public" &&
      c.status === "invited" &&
      !c.opponentId &&                          // 未被认领、未定向
      c.challengerId !== userId &&              // 不显示自己发的
      new Date(c.expiresAt).getTime() > now     // 未过期
    )
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

  const page = open.slice(offset, offset + limit).map((c) => publicChallenge(c, userId));
  json(res, 200, { total: open.length, items: page });
}

// ── 获取单个挑战
async function handleGet(req, res, id, userId) {
  const db = await readDB();
  const c  = db.challenges.find((c) => c.id === id);
  if (!c) return json(res, 404, { error: "not found" });
  if (c.challengerId !== userId && c.opponentId !== userId)
    return json(res, 403, { error: "forbidden" });
  json(res, 200, publicChallenge(c, userId));
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
      return json(res, 200, publicChallenge(c, userId));
    }

    if (c.status !== "invited") return json(res, 409, { error: "cannot edit after accepted" });
    if (body.title)          c.title          = body.title;
    if (body.targetCalories !== undefined) {
      const t = Number(body.targetCalories);
      if (!Number.isFinite(t) || t <= 0) return json(res, 400, { error: "targetCalories must be a positive number" });
      c.targetCalories = Math.max(1, Math.round(t));
    }
    if (body.durationDays)   c.durationDays   = Math.max(1, Number(body.durationDays) || 1);
    if (body.expiresAt)      c.expiresAt      = body.expiresAt;
    if (body.note !== undefined) c.note       = body.note || null;

    await writeDB(db);
    json(res, 200, publicChallenge(c, userId));
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

  const claimer = await findUserById(userId);

  await withPKLock(async () => {
    const db = await readDB();
    const c  = db.challenges.find((c) => c.inviteCode === inviteCode && c.status === "invited");
    if (!c) return json(res, 404, { error: "invite code not found or already claimed" });
    if (c.challengerId === userId) return json(res, 409, { error: "cannot claim your own challenge" });
    // 定向挑战（已指定对手）不允许他人用邀请码抢领
    if (c.opponentId && c.opponentId !== userId) {
      return json(res, 409, { error: "该挑战已指定对手" });
    }
    if (new Date(c.expiresAt) < new Date()) {
      c.status = "expired";
      await writeDB(db);
      return json(res, 410, { error: "invite has expired" });
    }

    c.opponentId       = userId;
    c.opponentName     = opponentName;
    c.opponentCode     = opponentCode || null;
    c.opponentUsername = claimer?.username || null;
    c.status           = "accepted";
    c.acceptedAt       = new Date().toISOString();
    await writeDB(db);

    // 通知发起方
    if (c.challengerDeviceToken) {
      sendPush(c.challengerDeviceToken, {
        title: "挑战已被认领！",
        body:  `${opponentName} 接受了你的挑战「${c.title}」，开始磨平吧！`,
        data:  { challengeId: c.id, type: "challenge_accepted" },
      }).catch(() => {});
    }

    json(res, 200, publicChallenge(c, userId));
  });
}

// ── 接受定向挑战（被指定的好友直接接受，不需邀请码）
async function handleAcceptDirected(req, res, id, userId, sendPush) {
  const accepter = await findUserById(userId);
  await withPKLock(async () => {
    const db = await readDB();
    const c  = db.challenges.find((c) => c.id === id);
    if (!c) return json(res, 404, { error: "not found" });
    if (c.status !== "invited") return json(res, 409, { error: "挑战已不可接受" });
    if (c.opponentId !== userId) return json(res, 403, { error: "该挑战不是发给你的" });
    if (new Date(c.expiresAt) < new Date()) {
      c.status = "expired";
      await writeDB(db);
      return json(res, 410, { error: "挑战已过期" });
    }

    c.opponentName = accepter?.profile?.displayName || c.opponentName;
    c.status       = "accepted";
    c.acceptedAt   = new Date().toISOString();
    await writeDB(db);

    if (c.challengerDeviceToken) {
      sendPush(c.challengerDeviceToken, {
        title: "好友接受了挑战！",
        body:  `${c.opponentName} 接受了你的挑战「${c.title}」`,
        data:  { challengeId: c.id, type: "challenge_accepted" },
      }).catch(() => {});
    }
    json(res, 200, publicChallenge(c, userId));
  });
}

// #5：进度防作弊常数。
// 进度由客户端上报，服务端无可信来源完全核实；以下为「提高作弊门槛」的硬化，
// 而非密码学级保证。真正杜绝需服务端依据可信 HealthKit 数据记账。
const MAX_KCAL_PER_SEC = 1.0;   // 60 kcal/min —— 远超任何可持续真实消耗，真实用户绝不会触顶
const PROGRESS_BURST_BUFFER = 100; // 允许的瞬时缓冲，保证小幅正常更新永不误伤

// ── 更新进度
async function handleUpdateProgress(req, res, id, userId, sendPush) {
  const body     = await readBody(req);
  const reported = Number(body.progress);
  if (!Number.isFinite(reported) || reported < 0) {
    return json(res, 400, { error: "progress must be a non-negative number" });
  }

  await withPKLock(async () => {
    const db = await readDB();
    const c  = db.challenges.find((c) => c.id === id);
    if (!c) return json(res, 404, { error: "not found" });
    if (c.status !== "accepted") return json(res, 409, { error: "challenge not active" });

    const isChallenger = c.challengerId === userId;
    const isOpponent   = c.opponentId   === userId;
    if (!isChallenger && !isOpponent) return json(res, 403, { error: "forbidden" });

    const now      = Date.now();
    const curKey   = isChallenger ? "challengerProgress"   : "opponentProgress";
    const tsKey    = isChallenger ? "challengerProgressAt" : "opponentProgressAt";
    const current  = c[curKey] || 0;
    const lastAt   = c[tsKey] ? new Date(c[tsKey]).getTime()
                              : new Date(c.acceptedAt || c.createdAt).getTime();

    // 1) 单调不回退：忽略比当前还低的上报
    let next = Math.max(current, reported);
    // 2) 封顶到目标值：存超过目标无意义
    next = Math.min(next, c.targetCalories);
    // 3) 按真实时间限速：本次增量不得超过 已过秒数 × 上限速率 + 缓冲
    const elapsedSec = Math.max(0, (now - lastAt) / 1000);
    const maxDelta   = elapsedSec * MAX_KCAL_PER_SEC + PROGRESS_BURST_BUFFER;
    next = Math.min(next, current + maxDelta);
    next = Math.round(next);

    c[curKey] = next;
    c[tsKey]  = new Date(now).toISOString();

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
    json(res, 200, publicChallenge(c, userId));
  });
}

// ── 注册 APNs device token
async function handleRegisterDeviceToken(req, res, id, userId) {
  const body        = await readBody(req);
  const deviceToken = String(body.deviceToken || "").trim();
  if (!deviceToken) return json(res, 400, { error: "deviceToken required" });
  // #6：APNs device token 必须是 64 位十六进制。未校验会被拼进 apns.js 的
  // 请求路径 `/3/device/${deviceToken}`，特殊字符可污染发往 Apple 的请求。
  if (!/^[0-9a-fA-F]{64}$/.test(deviceToken)) {
    return json(res, 400, { error: "invalid device token format" });
  }

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

// ── 排行榜：基于 PK 数据聚合（胜场 + 挑战内累计消耗）
//    胜场 = 完成的挑战中自己这侧达标；消耗 = 自己各挑战进度之和（服务端已存）。
export async function handleLeaderboard(req, res, url, userId) {
  const limit = Math.max(1, Math.min(100, Number(url.searchParams.get("limit")) || 20));
  const db = await readDB();
  const userMap = await getPublicUserMap();

  const stats = new Map(); // id -> { wins, burned, completed }
  const bump = (id, key, n = 1) => {
    if (!id) return;
    const s = stats.get(id) || { wins: 0, burned: 0, completed: 0 };
    s[key] += n;
    stats.set(id, s);
  };

  for (const c of db.challenges) {
    const target = c.targetCalories || 0;
    bump(c.challengerId, "burned", c.challengerProgress || 0);
    if (c.opponentId) bump(c.opponentId, "burned", c.opponentProgress || 0);
    if (c.status === "completed") {
      const challengerWon = target > 0 && (c.challengerProgress || 0) >= target;
      const opponentWon   = target > 0 && (c.opponentProgress || 0) >= target;
      if (challengerWon) bump(c.challengerId, "wins");
      if (opponentWon)   bump(c.opponentId, "wins");
      bump(c.challengerId, "completed");
      if (c.opponentId) bump(c.opponentId, "completed");
    }
  }

  const myInfo = userMap.get(userId);
  const items = [...stats.entries()]
    .map(([id, s]) => {
      const info = userMap.get(id);
      return info ? { username: info.username, displayName: info.displayName, ...s } : null;
    })
    .filter(Boolean)
    .sort((a, b) => b.wins - a.wins || b.burned - a.burned)
    .slice(0, limit)
    .map((row, i) => ({
      rank: i + 1,
      username: row.username,
      displayName: row.displayName,
      wins: row.wins,
      burned: row.burned,
      completed: row.completed,
      isMe: myInfo ? row.username === myInfo.username : false,
    }));

  json(res, 200, { items });
}
