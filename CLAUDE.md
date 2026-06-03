# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

磨平 (LevelIt) — Watch-First 健康 App，把卡路里摄入游戏化为"运动债务"。拍食物照片 → AI 估算热量 → 在 Apple Watch 上运动还债。iPhone 负责任务创建和监控，Watch 是唯一的运动执行端。

当前版本 0.4.1，处于 App Store 上架准备阶段。

## Build & Run

```bash
# 提交前必须过三关：共享测试、Xcode 工程解析、iPhone + embedded Watch 完整构建
scripts/verify-three-gates.sh

# 快速预检，仅用于开发中；提交前不能跳过完整构建
scripts/verify-three-gates.sh --skip-build

# 安装本地 pre-commit hook，commit 时自动跑轻量预检
scripts/install-git-hooks.sh
```

目标平台: iOS 17+, watchOS 10+。纯 Apple 框架，无第三方 CocoaPods/SPM 依赖。

详见 `QUALITY_GATES.md` 和 `ENGINEERING_WORKFLOW.md`。同步敏感改动还必须手测 iPhone 创建/编辑/删除任务、Watch 开始/暂停/完成运动、HealthKit 导入去重。

## Architecture

### 三层代码结构

```
LevelItShared/          Swift Package — 跨平台共享代码
├── Sources/Models/     DebtTask(@Model), TaskStatus, TaskMode, UserProfile 等
├── Sources/StateMachine/ TaskStateMachine(状态转换表), CalorieCalculator
├── Sources/Data/       PresetFoodLibrary(46种预设), MotivationalQuotes
├── Sources/Constants/  AppConstants(WC消息类型, 阈值常量)
└── Tests/              10 个测试 Suite

LevelIt/LevelIt/        iPhone App
├── Core/               AppRouter(路由枚举), AppLifecycleCoordinator, DesignTokens, PopToRoot
├── Features/           按功能组织的 View (Home/, Scan/, Analysis/, TaskMode/, Result/ 等)
└── Services/           WCSyncService, FoodAnalysisService, HealthKitImportService 等

LevelIt/LevelItWatch Watch App/  Watch App
├── Features/           TaskInbox/, QuickAdd/, Workout/, Completion/
├── Services/           WatchSyncReceiver, WatchHealthKitManager, WatchHapticManager
└── Complication/       WidgetKit 表盘组件
```

### 核心数据流

```
iPhone 拍照/手选 → FoodAnalysisResult → TaskModeView → DebtTask 创建 → WCSyncService → Watch
Watch 快选 → DebtTask 创建(跳过 synced) → WatchSyncReceiver → iPhone

运动中: Watch HKWorkoutSession → WatchHealthKitManager → sendProgress(双通道) → iPhone 只读监控
完成后: Watch status→completed→settled → WCSyncService → iPhone 弹出结清通知
```

### 8-State FSM (`TaskStateMachine`)

```
created → synced → inProgress ⇄ paused → completed → settled
  ↓         ↓                                          (终态)
expired   expired   cancelled ←──────────────────── cancelled
(终态)    (终态)      (终态)
```

- Watch 独立创建: `created → inProgress`（跳过 synced）
- 48h 未开始: `created/synced → expired`
- 终态: settled, cancelled, expired（不可再转换）
- **所有状态转换必须通过 `TaskStateMachine.transition()`**，直接改 status 会绕过副作用（completedAt/expiredAt 赋值）

### WatchConnectivity 三层同步

| 层 | API | 用途 | 频率 |
|---|---|---|---|
| L1 | `transferUserInfo` | 任务创建/更新/删除 | 事件驱动，可靠队列 |
| L2 | `sendMessage` | 实时运动进度 | 5 秒（仅前台可达时） |
| L2b | `updateApplicationContext` | 进度快照备份 | 每 5 秒覆盖 |
| L3 | `performFullSync` | 全量对账 + 孤儿检测 | App 激活时，10 秒节流 |

- iPhone 端: `WCSyncService`（发送 + 接收 + 全量同步）
- Watch 端: `WatchSyncReceiver`（接收 + 发送进度 + 孤儿恢复）
- 去重: `(taskId, _wcTimestamp)` 组合，旧时间戳的消息被丢弃
- 消息类型: `_wcType` 字段区分，定义在 `AppConstants.WCMessageType`

### 数据持久化

- **SwiftData**: `DebtTask`(@Model), `Achievement`(@Model), `UserStats`(@Model) — ModelContainer 在 App 入口初始化
- **UserDefaults**: `UserProfile`(通过 `UserProfileStore`), `NaturalAllowance`(每日自然消耗追踪), `ImportedWorkoutLedger`(HealthKit 导入去重)
- **文件系统**: `Documents/FoodImages/{taskId}.jpg` — 通过 `FoodImageStore` 管理
- **CloudKit**: 存根实现，当前返回 nil。升级到付费 Developer 账号后启用

### AI 食物识别链路

```
ScanView(拍照) → UIImage 压缩(512px, JPEG 0.7)
  → FoodAnalysisService.analyze() → POST http://39.105.196.84/api/analyze
  → 阿里云 ECS 北京 (Ubuntu 24.04 + Node 22 + systemd) → DashScope Kimi-K2.5 Vision
  → 返回 {foodName, foodEmoji, estimatedCalories, confidence}
  → confidence < 0.3 → AnalysisError.notFood
  → calories 钳位到 [10, 5000]
```

代理项目在 `../levelit-proxy/`，API Key 不暴露在客户端。
- **主**: 阿里云 ECS `http://39.105.196.84/api/analyze`（systemd 守护，`server.js` + `api/analyze-core.js`）
- **Fallback**: Vercel `https://levelit-proxy.vercel.app/api/analyze`（`api/analyze.js` 共用 analyze-core.js 逻辑）
- Info.plist 已为该 IP 配 ATS 例外（明文 HTTP）；上 App Store 前需补自签 TLS

## Key Patterns

- **单例服务**: `WCSyncService.shared`, `WatchHealthKitManager.shared`, `HealthKitDataStore.shared` 等，私有 init + static 属性
- **AppLifecycleCoordinator**: 统一管理启动和前台恢复逻辑，避免散落在各 View 中。启动时: WC configure → ensureStats → 过期检查 → 全量同步。回到前台时: 同步 + HK 缓存失效 + 过期检查
- **类型安全路由**: `AppRoute` 枚举 + `NavigationStack(path:)` + `.navigationDestination(for:)`，不使用 untyped arguments
- **Watch-First**: iPhone 运动中纯只读监控，运动控制权完全在 Watch。iPhone 降级模拟仅在无 Watch 配对时启用
- **popToRoot**: Environment key 让深层子页面可以弹回首页
- **设计 Token**: `DS.Colors`, `DS.Spacing`, `DS.Radius` — 所有 View 统一引用

### HealthKit

- **Watch**: `HKWorkoutSession` + `HKLiveWorkoutBuilder`，实时 activeEnergyBurned + heartRate
- **iPhone**: `HealthKitImportService` 查询今日外部运动（通过 bundleIdentifier 排除本 App 记录）
- **Session Recovery**: `WatchHealthKitManager.checkForRecoverableSession()` — 系统杀 App 后恢复活跃 workout（P0 待完善）
- **降级**: HealthKit 授权拒绝或 30 秒无数据 → `MockWorkoutService`（保守 8-15 kcal/min 模拟）

## Known Issues (see TODOS.md)

- **P0**: Session Recovery 尚未完整实现 — watchOS 杀后台 App 后需恢复运动状态
- **P0**: App Icon + 启动屏 + App Store 截图 + TestFlight 内测
- CloudKitService 是存根，UserProfile 仅本地存储
- CalorieCalculator 使用固定系数，尚未基于用户体重/性别个性化（P2）
