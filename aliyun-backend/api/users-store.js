/**
 * 只读访问 users.json 的共享小模块。
 * 供 social.js / pk.js 按 username 或 id 解析用户，避免与 server.js 形成循环依赖。
 * 仅做查询，不写——用户写操作仍归 server.js（注册/改名等带锁）。
 */
import { promises as fs } from "node:fs";

const DB_FILE = process.env.LEVELIT_DB_FILE || "./levelit-users.json";

async function readUsers() {
  try {
    const raw = await fs.readFile(DB_FILE, "utf8");
    if (!raw.trim()) return { users: [] };
    return JSON.parse(raw);
  } catch (e) {
    if (e.code === "ENOENT") return { users: [] };
    throw e;
  }
}

export async function findUserByUsername(username) {
  const uname = String(username || "").trim().toLowerCase();
  if (!uname) return null;
  const db = await readUsers();
  return db.users.find(u => u.username === uname) || null;
}

export async function findUserById(id) {
  if (!id) return null;
  const db = await readUsers();
  return db.users.find(u => u.id === id) || null;
}

/** 只暴露公开信息（用户名 + 昵称），绝不含内部 id / identifier */
export function publicUserInfo(u) {
  if (!u) return null;
  return {
    username: u.username || null,
    displayName: u.profile?.displayName || u.username || "用户",
  };
}
