# 磨平 LevelIt — 账号体系与社交 PK 版本总结 (v0.6.0)

> 适用版本：MARKETING_VERSION 1.0 / build 1
> Bundle：`xxxx.LevelIt`（iPhone）、`xxxx.LevelIt.watchkitapp`（Watch）
> 平台：iOS 17.0+ / watchOS 10.0+
> 后端：阿里云 ECS（39.105.196.84），Node.js 无框架 HTTP 服务
> 文档日期：2026-06

本版本在 v0.5.0（食物摄入管理）基础上，新增**独立账号体系**、**朋友 PK 社交玩法**与一轮**安全加固**。本文汇总需求、设计、架构与预期结果，作为该版本的交付与上架依据。

---

## 1. 需求背景与目标

磨平此前是纯本地 App（SwiftData 单机存储）。本版本要解决三件事：

1. **账号与跨设备**：用户能注册/登录，把注册资料与磨平数据存到云端，换设备可恢复。对用户隐藏具体云服务商（"独立系统，只是把数据存在云上"），措辞与服务商解耦，未来可随时切换。
2. **社交化 PK**：把单机的"磨平"变成可与朋友互动的挑战。要求：邀请码配对、好友体系、按用户名直接挑战、公开广场发榜认领、全站排行榜；且发起的挑战在被接受前可改/可删/可管理。
3. **安全底线**：在引入账号和社交后，对认证与接口做一次完整审计并修复高危项。

---

## 2. 功能清单

### 2.1 账号体系
- 邮箱/手机号 + 密码注册、登录；JWT（HMAC-SHA256，30 天）会话。
- 档案（性别/年龄/身高/体重/活动水平 + AI 估算 TDEE）随账号云端同步。
- 启动时静默恢复档案；**离线不强制登出**（仅 `missingSession` / HTTP 401 才登出）。
- 所有界面文案与服务商解耦（移除全部"阿里云/阿里后台"等用户可见字样）。

### 2.2 注册体验优化
- 年龄/身高/体重由横向滑条改为**三列滚轮选择器**，数值更易选准。
- 注册分步页用 `ZStack + switch` 替代 `TabView(.page)`，消除"全部页面预渲染导致的卡顿"。

### 2.3 朋友 PK —— 五种配对路径
| 路径 | 说明 |
|---|---|
| 邀请码 | 发起方生成**服务端邀请码**，对方输入认领 |
| 用户名搜索加好友 | 服务端唯一 username，搜人 → 好友请求 → 接受 |
| 定向好友挑战 | 直接对某位好友发起，对方在 PK 中心「接受挑战」 |
| 发榜广场 | 勾选「发布到广场」→ 任何人浏览并认领 |
| —— | 认领后双方实时同步进度，先达标者完成 |

挑战生命周期：`invited`（待认领/待接受）→ `accepted`（进行中）→ `completed` / `cancelled` / `expired` / `rejected`。待认领前可**编辑、撤回、删除、重新分享**。

### 2.4 排行榜
- 基于 PK 数据聚合：**胜场**（完成挑战中己方达标）为主、**累计消耗**为次，排序取前 N。
- 高亮"我"所在行，金/银/铜名次配色。

### 2.5 安全加固（详见 §7）
- AI 端点鉴权、token 迁 Keychain、PK 进度防作弊、deviceToken 校验、账号枚举缓解、密钥不轮换、内部 userId 不外泄、输入校验等。

---

## 3. 系统架构

```
┌──────────────┐         ┌──────────────────────────── 阿里云 ECS ────────────────────────────┐
│  iPhone App  │         │                                                                      │
│ (SwiftUI +   │  HTTP   │  levelit-proxy  :80   ── catch-all /api/* ──▶  auth backend :3000     │
│  SwiftData)  ├────────▶│  ├ /api/analyze            (本地处理, 鉴权)     ├ /api/auth/*           │
│              │         │  ├ /api/estimate-daily..   (本地处理, 鉴权)     ├ /api/pk/*             │
│  ┌────────┐  │         │  └ 其余 /api/* 转发到 :3000                     ├ /api/users/search     │
│  │ Watch  │  │  WC     │                                                ├ /api/friends/*        │
│  └────────┘  │◀───────▶│  APNs HTTP/2 ◀── 推送 ──┐                       └ /api/leaderboard      │
└──────────────┘  sync   │  JSON 存储: users.json / pk.json / social.json                         │
                         └──────────────────────────────────────────────────────────────────────┘
```

### 3.1 后端
- **运行时**：Node.js ≥20，原生 `http`，ESM，**零第三方依赖**（攻击面小）。
- **进程拓扑**：
  - `levelit-proxy`（80）：终端入口。本地处理两个 AI 端点（带委托鉴权），其余 `/api/*` 一律转发到 3000（catch-all，新增端点无需再改代理）。
  - `auth backend`（3000）：账号 + PK + 社交全部业务。
- **模块**：`server.js`（账号/路由）、`api/pk.js`（PK CRUD/广场/排行榜）、`api/social.js`（好友图）、`api/users-store.js`（只读用户解析，避免循环依赖）、`api/apns.js`（推送）。
- **存储**：文件型 JSON + Promise 串行写锁（`withDBLock`/`withPKLock`/social 锁），保证并发写安全。
- **认证**：PBKDF2（120k 迭代）密码哈希；JWT 自签（HMAC-SHA256）含 `exp`；`timingSafeEqual` 前置长度守卫。

### 3.2 iOS 客户端
- **UI**：SwiftUI，单一 `NavigationStack` + `AppRoute` 路由分发。
- **持久化**：SwiftData（`@Model` + `@Query`）；凭据存 **Keychain**（`AfterFirstUnlockThisDeviceOnly`）。
- **服务层**：
  - `AliyunAuthService` —— 注册/登录/档案/改名（命名保留历史，对用户不可见）。
  - `PKSyncService` —— 挑战 CRUD、认领、进度、设备 token、拉取合并（`fetchAllChallenges → RemoteChallenge` 纯值快照）。
  - `SocialService` —— 用户名/搜索/好友/广场/排行榜。
- **并发纪律**：所有 SwiftData `@Model` 仅在主 actor 访问；网络在 `await` 处挂起、续体回主 actor 写回，**绝不在后台线程碰模型**。
- **推送**：`AppDelegate` 接收 APNs token → `PKDeviceTokenStore` → 通知广播 → 注册到活跃挑战。
- **Watch**：WatchConnectivity 三层同步（既有能力）。

### 3.3 关键数据流
- **发起挑战**：本地构造 → `createChallenge`（服务端生成唯一 `inviteCode` 并回传）→ 写入 SwiftData → 展示真实邀请码。
- **接收挑战**：PK 中心 `.task` 调 `pullRemoteChallenges` 拉取服务端我参与的全部挑战 → 按 `serverId` 合并进本地 → 定向挑战显示「接受」。
- **进度同步**：`syncActiveChallenges` 主 actor 顺序推送己方进度、回写对手进度。

---

## 4. 数据模型

### 4.1 SwiftData @Model（客户端）
`DebtTask`、`MealIntake`、`Achievement`、`UserStats`、`AnomalyLog`、`ImportedWorkoutRecord`、`DailyCalorieBalance`、**`PKChallenge`**。

`PKChallenge` 本版本新增字段：`serverId`、`serverInviteCode`、`opponentProgress`、`isChallenger`、`myProgress`、`expiresAt`、状态扩展（`expired`/`rejected`）。

### 4.2 值类型 / 存储
- `AuthSession`（token/userId/identifier/**username**）—— Keychain。
- `UserProfile`（displayName/**inviteCode**/性别/年龄/身高/体重/活动水平/AI 估算）—— UserDefaults。
- 服务端 user：`{ id, identifier(唯一), username(唯一), passwordHash, profile }`。
- 服务端 challenge：含双方 id/username/进度/可见性/邀请码/过期时间/设备 token 等。
- 服务端 social：`{ links: [{ fromUserId, toUserId, status }] }`。

---

## 5. API 接口清单（均经 Bearer token，AI 与社交端点亦然）

**账号**
- `POST /api/auth/register`、`POST /api/auth/login`、`GET /api/auth/me`、`PUT /api/auth/profile`
- `PUT /api/auth/username`、`GET /api/users/search?q=`

**PK**
- `GET|POST /api/pk/challenges`、`GET|PUT|DELETE /api/pk/challenges/:id`
- `POST /api/pk/claim`、`GET /api/pk/board`
- `PUT /api/pk/challenges/:id/progress`、`/accept`、`/device-token`
- `GET /api/leaderboard`

**好友**
- `POST /api/friends/request`、`GET /api/friends/requests`
- `POST /api/friends/requests/:id/accept|reject`
- `GET /api/friends`、`DELETE /api/friends/:username`

**AI（levelit-proxy，已加鉴权）**
- `POST /api/analyze`、`POST /api/estimate-daily-energy`

---

## 6. 安全设计与审计结果

完整审计覆盖认证、越权、密钥、客户端泄露面。**已修复**：

| 编号 | 项 | 处理 |
|---|---|---|
| #2 | AI 端点无鉴权（可被刷量烧钱）| 委托验证（proxy → `/api/auth/me`），单一密钥源 |
| #4 | token 存 UserDefaults | 迁 Keychain，不进备份 |
| #5 | PK 进度可作弊 | 单调不回退 + 封顶 + 按真实时间限速 |
| #6 | deviceToken 未校验 | 64 位 hex 校验，pk.js + apns.js 双层 |
| #7 | 账号枚举 | 注册重复中性措辞（部分缓解）|
| #8 | 部署轮换 secret 登出全员 | 复用已有 secret |
| #9 | 暴露内部 userId | 响应去内部 id，仅 username/displayName |
| #10 | targetCalories 可存 NaN | 有限正数校验 |

**良好基线**：git 历史无泄密、后端零依赖、JWT 默认密钥在生产拒启动、`timingSafeEqual` 有长度守卫、PK 列表/详情无 IDOR、搜索/排行榜不泄露内部 id。

**仍待办（见 §9）**：#1 全程 HTTPS、#3 接口限流。

---

## 7. 测试与验证

- **认证回归**：`test-auth.js` 36/36 通过（注册/登录/鉴权/越权/并发注册竞态/过期 token 等）。
- **PK 审计**：11/11（进度防作弊钳制、deviceToken 校验、内部 id 不外泄、NaN 拒绝）。
- **username**：8/8（派生/查重/改名/搜索/不泄露 id）。
- **好友 + 定向 PK**：10/10（请求-接受、定向挑战可见与接受、第三方抢领被拒）。
- **广场 + 排行榜**：9/9（公开/私密过滤、自己可见、公开上限 429、排行榜不泄露 id）。
- **邀请码端到端**：服务端码可认领、伪造本地码被拒。
- **代理转发**：`/api/friends`、`/api/users/search`、`/api/leaderboard` 无 token 均 401（已转发到后端）。
- **iOS**：每次改动后 `xcodebuild` 构建通过。

---

## 8. 预期达成的结果

1. 用户可注册/登录，档案与磨平数据云端同步、换机恢复。
2. 五种方式与朋友建立 PK：邀请码、用户名搜索加好友、定向好友挑战、广场发榜认领。
3. 进行中挑战双进度条实时对比，先达标者完成；全站排行榜可见名次。
4. 待认领挑战可编辑/撤回/删除/重分享。
5. 接口在传输安全（HTTPS）以外的高危项已收敛；AI 端点不再可匿名刷量。

---

## 9. 已知限制与后续路线

| 优先级 | 项 | 说明 |
|---|---|---|
| **P0（上架前必做）** | **#1 全程 HTTPS** | 当前密码/token/食物照片/好友关系走明文 HTTP（含 ATS 例外）。**带真实用户前必须配域名 + 证书**。 |
| P1 | #3 接口限流 | 登录/注册/AI 端点无速率限制，需按 IP+账号限流。 |
| P1 | 账号删除 | Apple 5.1.1(v) 要求支持账号创建的 App 提供应用内删除账号；需补后端端点 + 设置页入口。 |
| P2 | 存储迁移 SQLite | 广场+排行榜+好友图并发上来后，单文件 JSON 会成瓶颈。 |
| P2 | 真机偶发卡死跟踪 | 历史多为 SwiftData 迁移/旧库状态；已加迁移兜底（删 .store/-wal/-shm 重建）与同步防重入；若复现需主线程堆栈定位。 |
| P3 | 推送上线 | 远程推送需付费账号加 Push Notifications capability + 服务端配 APNs 证书环境变量。 |
