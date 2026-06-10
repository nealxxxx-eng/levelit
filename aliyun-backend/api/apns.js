/**
 * APNs HTTP/2 push notification helper.
 *
 * Required env vars (all optional — missing = pushes silently skipped):
 *   APNS_KEY_PATH   — 绝对路径，指向从 Apple Developer Portal 下载的 .p8 私钥文件
 *   APNS_KEY_ID     — 10 位 Key ID（Developer Portal > Keys 页面）
 *   APNS_TEAM_ID    — 10 位 Team ID（Developer Portal > Membership）
 *   APNS_BUNDLE_ID  — App Bundle ID，如 com.yourcompany.levelit
 *   APNS_ENV        — "production"（App Store / TestFlight）或 "development"（默认，模拟器/直连真机）
 */
import https from "node:https";
import fs from "node:fs";
import crypto from "node:crypto";

const APNS_KEY_PATH  = process.env.APNS_KEY_PATH;
const APNS_KEY_ID    = process.env.APNS_KEY_ID;
const APNS_TEAM_ID   = process.env.APNS_TEAM_ID;
const APNS_BUNDLE_ID = process.env.APNS_BUNDLE_ID;
const APNS_ENV       = process.env.APNS_ENV || "development";

const isConfigured = APNS_KEY_PATH && APNS_KEY_ID && APNS_TEAM_ID && APNS_BUNDLE_ID;

if (!isConfigured) {
  console.warn("APNs: 未配置推送证书，push notification 功能已禁用。参见 aliyun-backend/api/apns.js 注释。");
}

// JWT token cache — APNs token 有效期 1 小时，缓存 50 分钟
let _cachedToken = null;
let _tokenExpiry  = 0;

function generateAPNsJWT() {
  if (!isConfigured) return null;
  const now = Math.floor(Date.now() / 1000);
  if (_cachedToken && now < _tokenExpiry) return _cachedToken;

  try {
    const privateKey = fs.readFileSync(APNS_KEY_PATH, "utf8");
    const header  = Buffer.from(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID })).toString("base64url");
    const payload = Buffer.from(JSON.stringify({ iss: APNS_TEAM_ID, iat: now })).toString("base64url");
    const unsigned = `${header}.${payload}`;
    const sign = crypto.createSign("SHA256");
    sign.update(unsigned);
    // APNs 要求 IEEE P1363 格式（64 字节原始签名，非 DER）
    const sig = sign.sign({ key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url");
    _cachedToken = `${unsigned}.${sig}`;
    _tokenExpiry = now + 50 * 60;
    return _cachedToken;
  } catch (err) {
    console.error("APNs JWT 生成失败:", err.message);
    return null;
  }
}

/**
 * 发送推送通知。
 * @param {string} deviceToken  — iOS 设备 token（十六进制字符串，不含空格）
 * @param {object} opts
 * @param {string} opts.title   — 通知标题
 * @param {string} opts.body    — 通知正文
 * @param {object} [opts.data]  — 附加数据（透传给 App）
 */
export async function sendPushNotification(deviceToken, { title, body, data = {} }) {
  // 纵深防御:token 会拼进请求路径,只接受合法十六进制,杜绝路径注入
  if (typeof deviceToken !== "string" || !/^[0-9a-fA-F]{64}$/.test(deviceToken)) {
    console.warn("APNs: 非法 device token,已跳过推送");
    return;
  }
  const jwt = generateAPNsJWT();
  if (!jwt) return; // 静默跳过

  const host = APNS_ENV === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";

  const payload = JSON.stringify({
    aps: { alert: { title, body }, sound: "default", badge: 1 },
    ...data,
  });

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        host,
        path: `/3/device/${deviceToken}`,
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": APNS_BUNDLE_ID,
          "apns-push-type": "alert",
          "apns-expiration": "0",
          "content-type": "application/json",
          "content-length": Buffer.byteLength(payload),
        },
      },
      (res) => {
        let responseBody = "";
        res.on("data", (chunk) => { responseBody += chunk; });
        res.on("end", () => {
          if (res.statusCode === 200) {
            resolve();
          } else {
            console.warn(`APNs 推送失败 HTTP ${res.statusCode}:`, responseBody);
            reject(new Error(`APNs ${res.statusCode}: ${responseBody}`));
          }
        });
      }
    );
    req.on("error", reject);
    req.write(payload);
    req.end();
  });
}
