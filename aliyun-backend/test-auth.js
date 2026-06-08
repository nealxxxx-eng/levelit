/**
 * Auth API 测试套件
 * 运行: node test-auth.js [BASE_URL]
 * 默认: http://localhost:3000
 *
 * 覆盖场景:
 *   - 正常注册/登录/获取用户/更新档案
 *   - 输入验证（缺字段、短密码）
 *   - 认证错误（无 token、错误 token、401）
 *   - 幂等性（重复注册 409）
 *   - identifier 大小写归一化
 *   - 并发注册竞态（Bug #2）
 *   - 登录失败时 verifyPassword 不崩溃（Bug #3）
 */

const BASE = process.argv[2] ?? "http://localhost:3000";

let passed = 0;
let failed = 0;
const failures = [];

// ─── 工具函数 ────────────────────────────────────────────────────────────────

async function req(method, path, body, token) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body != null ? JSON.stringify(body) : undefined,
  });
  let json;
  try {
    json = await res.json();
  } catch {
    json = null;
  }
  return { status: res.status, body: json };
}

function assert(name, condition, detail = "") {
  if (condition) {
    console.log(`  ✓ ${name}`);
    passed++;
  } else {
    console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ""}`);
    failed++;
    failures.push(name);
  }
}

function section(title) {
  console.log(`\n── ${title}`);
}

function uniqueId() {
  return `test_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
}

function sampleProfile(overrides = {}) {
  return {
    displayName: "测试用户",
    gender: "male",
    age: 25,
    heightCM: 175,
    weightKG: 70,
    activityLevel: "light",
    inviteCode: "TESTCODE",
    ...overrides,
  };
}

// ─── 测试组 ──────────────────────────────────────────────────────────────────

async function testHealth() {
  section("健康检查");
  const r = await req("GET", "/health");
  assert("GET /health → 200", r.status === 200);
  assert("响应包含 ok:true", r.body?.ok === true);
}

async function testRegisterHappyPath() {
  section("注册 — 正常流程");
  const id = uniqueId() + "@example.com";
  const r = await req("POST", "/api/auth/register", {
    identifier: id,
    password: "password123",
    profile: sampleProfile(),
  });
  assert("POST /api/auth/register → 201", r.status === 201, `got ${r.status}`);
  assert("返回 token 字符串", typeof r.body?.token === "string" && r.body.token.length > 10);
  assert("返回 userId 字符串", typeof r.body?.userId === "string");
  assert("返回 profile 对象", typeof r.body?.profile === "object");
  return { id, token: r.body?.token, userId: r.body?.userId };
}

async function testLoginHappyPath(id) {
  section("登录 — 正常流程");
  const r = await req("POST", "/api/auth/login", {
    identifier: id,
    password: "password123",
  });
  assert("POST /api/auth/login → 200", r.status === 200, `got ${r.status}`);
  assert("返回 token", typeof r.body?.token === "string");
  assert("返回 userId", typeof r.body?.userId === "string");
  return r.body?.token;
}

async function testGetMe(token) {
  section("获取当前用户");
  const r = await req("GET", "/api/auth/me", undefined, token);
  assert("GET /api/auth/me → 200", r.status === 200, `got ${r.status}`);
  assert("返回 userId", typeof r.body?.userId === "string");
  assert("返回 identifier", typeof r.body?.identifier === "string");
  assert("返回 profile", typeof r.body?.profile === "object");
}

async function testUpdateProfile(token) {
  section("更新档案");
  const updated = sampleProfile({ displayName: "更新后昵称", weightKG: 75 });
  const r = await req("PUT", "/api/auth/profile", { profile: updated }, token);
  assert("PUT /api/auth/profile → 200", r.status === 200, `got ${r.status}`);
  assert("displayName 已更新", r.body?.profile?.displayName === "更新后昵称");
  assert("weightKG 已更新", r.body?.profile?.weightKG === 75);
}

async function testValidationErrors() {
  section("输入验证");

  // 缺少 identifier
  let r = await req("POST", "/api/auth/register", {
    password: "password123",
    profile: sampleProfile(),
  });
  assert("注册：缺 identifier → 400", r.status === 400, `got ${r.status}`);

  // 密码太短
  r = await req("POST", "/api/auth/register", {
    identifier: uniqueId() + "@example.com",
    password: "abc",
    profile: sampleProfile(),
  });
  assert("注册：密码少于 6 位 → 400", r.status === 400, `got ${r.status}`);

  // 缺少 profile
  r = await req("POST", "/api/auth/register", {
    identifier: uniqueId() + "@example.com",
    password: "password123",
  });
  assert("注册：缺 profile → 400", r.status === 400, `got ${r.status}`);

  // 更新档案：缺少 profile 字段
  r = await req("PUT", "/api/auth/profile", {}, "fake-token");
  assert("更新档案：缺 profile → 非 200（401 或 400）", r.status !== 200);
}

async function testAuthErrors() {
  section("认证错误");

  // 无 token
  let r = await req("GET", "/api/auth/me");
  assert("无 token → 401", r.status === 401, `got ${r.status}`);

  // 随机字符串 token
  r = await req("GET", "/api/auth/me", undefined, "this-is-not-a-token");
  assert("无效 token → 401", r.status === 401, `got ${r.status}`);

  // 格式正确但签名错误
  const fakePayload = Buffer.from(JSON.stringify({ sub: "fake-id", iat: 0, nonce: "x" })).toString("base64url");
  const fakeToken = `${fakePayload}.invalidsignature`;
  r = await req("GET", "/api/auth/me", undefined, fakeToken);
  assert("篡改签名的 token → 401", r.status === 401, `got ${r.status}`);

  // 正确格式 Bearer 前缀但 token 无效
  r = await req("GET", "/api/auth/me", undefined, "");
  assert("空 token → 401", r.status === 401, `got ${r.status}`);
}

async function testLoginErrors() {
  section("登录错误");
  const id = uniqueId() + "@example.com";

  // 先注册
  await req("POST", "/api/auth/register", {
    identifier: id,
    password: "correctpass",
    profile: sampleProfile(),
  });

  // 错误密码
  let r = await req("POST", "/api/auth/login", {
    identifier: id,
    password: "wrongpassword",
  });
  assert("错误密码 → 401", r.status === 401, `got ${r.status}`);

  // 不存在的账号
  r = await req("POST", "/api/auth/login", {
    identifier: "nonexistent_" + uniqueId() + "@example.com",
    password: "password123",
  });
  assert("不存在的账号 → 401", r.status === 401, `got ${r.status}`);
}

async function testDuplicateRegistration() {
  section("重复注册（幂等性）");
  const id = uniqueId() + "@example.com";
  const body = {
    identifier: id,
    password: "password123",
    profile: sampleProfile(),
  };
  const r1 = await req("POST", "/api/auth/register", body);
  const r2 = await req("POST", "/api/auth/register", body);
  assert("第一次注册 → 201", r1.status === 201, `got ${r1.status}`);
  assert("重复注册同 identifier → 409", r2.status === 409, `got ${r2.status}`);
}

async function testIdentifierNormalization() {
  section("identifier 大小写归一化");
  const base = uniqueId();
  const id = `${base}@Example.COM`;

  // 用大写注册
  await req("POST", "/api/auth/register", {
    identifier: id,
    password: "password123",
    profile: sampleProfile(),
  });

  // 用小写登录
  const r = await req("POST", "/api/auth/login", {
    identifier: id.toLowerCase(),
    password: "password123",
  });
  assert("大写注册后用小写登录 → 200", r.status === 200, `got ${r.status}`);

  // 重复注册小写版本 → 应该 409
  const r2 = await req("POST", "/api/auth/register", {
    identifier: id.toLowerCase(),
    password: "password123",
    profile: sampleProfile(),
  });
  assert("大写/小写视为同一账号，重复注册 → 409", r2.status === 409, `got ${r2.status}`);
}

async function testIdentifierWithWhitespace() {
  section("identifier 首尾空格处理");
  const base = uniqueId() + "@example.com";
  await req("POST", "/api/auth/register", {
    identifier: base,
    password: "password123",
    profile: sampleProfile(),
  });
  const r = await req("POST", "/api/auth/login", {
    identifier: `  ${base}  `,
    password: "password123",
  });
  assert("带首尾空格的 identifier 登录 → 200", r.status === 200, `got ${r.status}`);
}

async function testConcurrentRegistration() {
  section("并发注册竞态条件 [Bug #2]");
  const id = uniqueId() + "@example.com";
  const body = {
    identifier: id,
    password: "password123",
    profile: sampleProfile(),
  };

  // 同时发出 10 个相同 identifier 的注册请求
  const results = await Promise.all(
    Array.from({ length: 10 }, () =>
      req("POST", "/api/auth/register", body)
    )
  );

  const successCount = results.filter(r => r.status === 201).length;
  const conflictCount = results.filter(r => r.status === 409).length;

  assert(
    `10 个并发请求只有 1 个成功（实际 ${successCount} 个成功）`,
    successCount === 1,
    `成功: ${successCount}, 冲突: ${conflictCount}`
  );

  if (successCount > 1) {
    console.error(
      `    ⚠ 竞态条件确认：${successCount} 个请求都拿到了 201，DB 中存在重复账号`
    );
  }
}

async function testMalformedPasswordHash() {
  section("verifyPassword 健壮性 [Bug #3]");
  // 这个 bug 需要直接操作 DB 文件，用户名不存在 → 返回 401 而不是 500
  // 这里只测试"不存在账号"不会崩溃（能正常返回 401）
  const r = await req("POST", "/api/auth/login", {
    identifier: "ghost_" + uniqueId() + "@example.com",
    password: "password123",
  });
  assert(
    "登录不存在账号返回 401 而非 500",
    r.status === 401,
    `got ${r.status}`
  );
  // 注：完整测试需在 DB 中手动写入格式错误的 passwordHash，此处记录为人工测试项
  console.log("    ℹ 完整 Bug #3 测试需人工操作：在 levelit-users.json 中将某用户 passwordHash 改为 'badsalt' 再登录，观察是否返回 500 而非 401");
}

async function testTokenFromDifferentUser() {
  section("Token 隔离（跨用户访问）");
  // 注册用户 A，用 A 的 token 更新档案 → 只能改 A 的数据
  const idA = uniqueId() + "@example.com";
  const rA = await req("POST", "/api/auth/register", {
    identifier: idA,
    password: "password123",
    profile: sampleProfile({ displayName: "用户A" }),
  });
  const tokenA = rA.body?.token;

  const r = await req("GET", "/api/auth/me", undefined, tokenA);
  assert("用 A 的 token 只能获取 A 的数据", r.body?.identifier === idA.toLowerCase(), `got ${r.body?.identifier}`);
}

async function testNotFoundRoute() {
  section("未知路由");
  const r = await req("GET", "/api/nonexistent");
  assert("未知路由 → 404", r.status === 404, `got ${r.status}`);
}

async function testExpiredToken() {
  section("过期 token [Bug #4]");
  // 手动构造一个 exp 在过去的 token（签名用默认 secret，仅本地测试有效）
  const secret = process.env.LEVELIT_AUTH_SECRET ?? "replace-this-before-deploy";
  const payload = { sub: "fake-user", iat: 1000, exp: 1001, nonce: "x" };
  const encoded = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const { createHmac } = await import("node:crypto");
  const signature = createHmac("sha256", secret).update(encoded).digest("base64url");
  const expiredToken = `${encoded}.${signature}`;

  const r = await req("GET", "/api/auth/me", undefined, expiredToken);
  assert("过期 token → 401", r.status === 401, `got ${r.status}`);
}

// ─── 主函数 ──────────────────────────────────────────────────────────────────

async function main() {
  console.log(`\n🧪 LevelIt Auth 测试套件`);
  console.log(`   目标: ${BASE}\n`);

  // 先检查服务是否在线
  try {
    await fetch(`${BASE}/health`, { signal: AbortSignal.timeout(3000) });
  } catch {
    console.error(`❌ 无法连接到 ${BASE}，请先启动服务：\n   node server.js\n`);
    process.exit(1);
  }

  await testHealth();

  // 正常流程
  const { id, token: registerToken } = await testRegisterHappyPath();
  const loginToken = await testLoginHappyPath(id);
  await testGetMe(loginToken);
  await testUpdateProfile(loginToken);

  // 错误处理
  await testValidationErrors();
  await testAuthErrors();
  await testLoginErrors();

  // 幂等性 & 归一化
  await testDuplicateRegistration();
  await testIdentifierNormalization();
  await testIdentifierWithWhitespace();

  // 隐藏 bug 专项测试
  await testConcurrentRegistration();
  await testMalformedPasswordHash();
  await testTokenFromDifferentUser();
  await testExpiredToken();
  await testNotFoundRoute();

  // ─── 结果汇总
  console.log(`\n${"─".repeat(50)}`);
  console.log(`结果: ${passed} 通过 / ${failed} 失败\n`);

  if (failures.length > 0) {
    console.error("失败用例:");
    failures.forEach(f => console.error(`  • ${f}`));
  }

  // ─── iOS 客户端手工测试清单（无法自动化）
  console.log(`
📱 iOS 客户端手工测试清单
─────────────────────────
[ ] Bug #1 — 断网自动登出：
    1. 登录后进主页
    2. 开启飞行模式
    3. 强杀 App 后重新打开
    预期：仍显示主页（静默忽略网络错误）
    当前：30 秒后 token 被清除，跳回登录页

[ ] inviteCode 闪烁（Bug #6）：
    1. 进入"设置"页面
    2. 观察邀请码区域
    预期：直接显示已保存的邀请码
    当前：先显示一个随机新码，随后 onAppear 替换为正确值

[ ] Token 隔离：
    1. 账号 A 登录，修改档案体重 → 保存
    2. 账号 A 退出，账号 B 登录
    3. 账号 B 档案体重应与 A 修改无关

[ ] 连续快速点击"开始使用"（注册）：
    1. 在摘要页面快速点击两次"开始使用"
    预期：只发一个注册请求
    当前：isSaving 保护应能防止，需确认

[ ] 设置页保存后再进入：
    1. 修改档案 → 保存
    2. 退出设置 → 重新进入设置
    预期：显示上次保存的值
`);

  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error("测试运行崩溃:", err);
  process.exit(2);
});
