# 磨平 LevelIt — 架构文档

> 更新日期: 2026-03-24
> 版本: 0.4.1

## 产品定位

**拍一下你要吃的东西，看看你得动多久。**

Watch-First 健康应用：iPhone 创建任务、Watch 独立运动、双端实时同步。

## 架构概览 (四层结构)

```
  iPhone (管理/数据聚合)             Watch (运动执行)
  +----------------------+          +------------------+
  | 拍照 + AI 识别        |          | 独立接单          |
  | 手动选食物            |          | 12种运动模式      |
  | 美食墙/统计/今日页     |<--WC--->| HealthKit运动     |
  | HealthKit 外部导入     |          | 心率实时显示      |
  | 任务管理 (删除/抵扣)   |          | Haptic+励志文案    |
  | 本地通知 (3次/日)      |          | 独立结清          |
  +----------------------+          +------------------+
          |                                |
          v                                v
  +----------------------------------------------+
  |    Local SwiftData (各端独立持久化)            |
  |    DebtTask, UserStats, Achievement           |
  |    Documents/FoodImages/{taskId}.jpg          |
  +----------------------------------------------+
          |                                |
          +------ WatchConnectivity --------+
          | transferUserInfo (任务/状态/删除) |
          | sendMessage (实时进度)            |
          | applicationContext (最新状态)     |
          +----------------------------------+
          |
          v
  +----------------------------------------------+
  |    服务端边界 (Vercel Serverless, hkg1)        |
  |    POST /api/analyze → Qwen3.5-Plus Vision   |
  |      → AI 结果返回 iPhone                      |
  |      → 图片+结果存入 Cloudflare R2             |
  |    GET /privacy → 隐私政策 HTML                |
  +----------------------------------------------+
```

## 技术栈

| 层 | iPhone | Watch | 服务端 |
|----|--------|-------|--------|
| UI | SwiftUI (TabView 三页) | SwiftUI | — |
| 数据 | SwiftData (@Model) | SwiftData (@Model) | — |
| 同步 | WCSyncService | WatchSyncReceiver | — |
| 运动 | HealthKitImportService (读取外部) | WatchHealthKitManager (HKWorkoutSession) | — |
| AI | FoodAnalysisService | — | Vercel → DashScope |
| 存储 | FoodImageStore (本地) | — | Cloudflare R2 |
| 通知 | NotificationScheduler | — | — |
| 相机 | AVCaptureSession | — | — |
| 反馈 | — | WKInterfaceDevice Haptic | — |

## iPhone 首页三页滑动

```
←滑 [统计页] ←→ [首页] ←→ [今日页] 滑→
     周/月统计    任务列表    今日汇总
     热量趋势    CTA按钮     朋友PK预留
     运动Top3    运动导入
```

## 方案 B: Watch-First 设计

| 功能 | iPhone | Watch |
|------|--------|-------|
| 创建任务 | 拍照/手动选择 | 快速接单 |
| 运动 | **不运动** (只读监控) | **唯一运动端** |
| 查看进度 | 接收 Watch 进度 | 实时显示 + 心率 |
| 结清 | 接收结果 | 运动完成后结清 |
| 降级 | 无 Watch 时 Mock 模拟 | — |

## 文件结构

```
~/CC/levelit/
├── LevelItShared/                    (Swift Package - 共享代码)
│   ├── Sources/
│   │   ├── Models/                   (DebtTask, TaskMode, TaskStatus, PresetFood, Achievement, UserStats)
│   │   ├── Logic/                    (TaskStateMachine, CalorieCalculator, MotivationalQuotes)
│   │   └── Constants/                (AppConstants + WCMessageType)
│   └── Tests/                        (10 suites, 111 tests)
│
├── LevelIt/LevelIt/                  (iPhone App - 30 files)
│   ├── Core/                         (AppRouter, ContentView, DesignTokens, PopToRoot)
│   ├── Features/
│   │   ├── Home/HomeView.swift       (TabView 三页: 统计/首页/今日)
│   │   ├── Stats/StatsView.swift     (周/月统计, 热量趋势图, 运动Top3)
│   │   ├── Today/TodayView.swift     (今日汇总, 朋友PK预留)
│   │   ├── Scan/                     (ScanView + CameraPreview + CameraManager)
│   │   ├── ManualSelect/             (预置食物库 + 搜索 + 自定义)
│   │   ├── Analysis/                 (AI 分析结果展示)
│   │   ├── TaskMode/                 (12种模式 + 常用置顶)
│   │   ├── TaskCreated/              ("已发送到手表"引导)
│   │   ├── TaskDetail/               (智能分流: 监控/等待/降级/结果)
│   │   ├── Progress/                 (降级模拟运动)
│   │   ├── Result/                   (结清动画 + 超额彩蛋 + 徽章)
│   │   ├── Share/                    (分享卡渲染)
│   │   ├── FoodWall/                 (美食墙 + 食物详情, 长按删除)
│   │   ├── TaskList/                 (历史任务, 状态筛选, 长按删除)
│   │   └── WorkoutImport/            (HealthKit 外部运动导入 + 抵扣)
│   ├── Services/
│   │   ├── FoodAnalysisService.swift (AI 识别: 压缩→代理→解析→校验)
│   │   ├── FoodImageStore.swift      (Documents/FoodImages/ 读写删)
│   │   ├── HealthKitImportService.swift (查询今日外部运动, 排除本App)
│   │   ├── NotificationScheduler.swift  (每日3次本地通知)
│   │   ├── WCSyncService.swift       (WC 同步: 任务/状态/删除)
│   │   ├── TaskExpiryService.swift   (48h 过期)
│   │   └── MockWorkoutService.swift  (降级模拟)
│   ├── LevelItApp.swift              (入口 + 通知调度)
│   └── LevelIt.entitlements          (HealthKit)
│
├── LevelIt/LevelItWatch Watch App/   (Watch App - 12 files)
│   ├── Features/
│   │   ├── TaskInbox/                (收件箱 + iPhone 任务通知)
│   │   ├── QuickAdd/                 (快速接单 + 常用模式置顶)
│   │   ├── Workout/                  (运动: 进度环+心率+暂停+自动完成)
│   │   └── Completion/               (结清/部分/超额)
│   ├── Complication/                 (WidgetKit 表盘)
│   └── Services/
│       ├── WatchHealthKitManager.swift (HKWorkoutSession + 心率)
│       ├── WatchSyncReceiver.swift   (WC 接收 + 路由: 同步/删除)
│       ├── WatchMockWorkoutService.swift
│       └── WatchHapticManager.swift
│
~/CC/levelit-proxy/                   (Vercel Serverless 代理)
    ├── api/
    │   ├── analyze.js                (AI识别 + R2存储)
    │   └── privacy.js                (隐私政策)
    ├── vercel.json                   (路由 + 香港节点 hkg1)
    └── package.json                  (@aws-sdk/client-s3)
```

## 数据模型

### DebtTask (核心)
```
id: String (unique)
foodName / foodEmoji / foodImageFileName
estimatedCalories / targetBurnCalories / estimatedMinutes
taskMode: TaskMode (12种)
status: TaskStatus (8种)
progressPercent / burnedCalories / durationSeconds
source: TaskSource (.iPhone / .watch)
isOverAchieved: Bool
createdAt / completedAt / expiredAt / lastSyncAt
```

### 状态机 (8 种状态)
```
created → synced → inProgress ↔ paused → completed → settled
created → inProgress (Watch 独立)
created/synced → expired (48h)
任意非终态 → cancelled
settled/cancelled/expired = 终态
```

## WatchConnectivity 同步

| 通道 | API | 用途 | 频率 |
|------|-----|------|------|
| L1 | transferUserInfo | 任务创建/状态变更/删除 | 事件驱动 |
| L2 | sendMessage | 实时进度推送 | 每 5 秒 |
| L2b | applicationContext | 最新进度快照 | 每 5 秒 |
| L3 | transferUserInfo | 可靠进度备份 | 每 30 秒 |

消息类型: `task_sync` / `task_delete` / `progress` / `ui_refresh`

## HealthKit 集成

### Watch 端 (运动执行)
- 12 种 HKWorkoutActivityType 映射
- 室内/户外自动判断 (locationType)
- HKLiveWorkoutBuilder 实时数据收集
- activeEnergyBurned + heartRate 读取 (typesToShare 含心率)
- 预热期间保守估算 (2 kcal/min)，真实数据到达后切换
- 授权被拒降级到 MockWorkoutService

### iPhone 端 (外部运动导入)
- 查询今日 HKWorkout，按 bundleIdentifier 排除本 App
- ImportedWorkoutLedger (UserDefaults) 按 UUID 去重，防止重复抵扣
- 导入走 updateProgress + TaskStateMachine + UserStats + WC 同步
- 权限在导入页首次触发，不在首页自动弹

## 服务端

### AI 识别流程
```
iPhone 拍照 → 压缩512px/JPEG0.7 → base64
  → POST /api/analyze (Vercel hkg1)
    → DashScope Qwen3.5-Plus Vision (Thinking 关闭)
    → 解析 JSON (foodName/emoji/calories/confidence)
    → 保存图片+结果到 R2 (await, 按日期分目录)
    → 返回结果给 iPhone
iPhone 校验: confidence < 0.3 判非食物, calories 钳位 10~5000
```

### R2 存储结构
```
levelit-data/
  2026-03-24/
    {timestamp}_{foodName}.jpg    ← 原始图片
    {timestamp}_{foodName}.json   ← 识别结果+元数据
```

### R2 隐私与数据治理
- 上传目的：食物照片仅用于 AI 食物识别、热量估算、质量排查和后续模型分析。
- 保存范围：R2 可保存照片、AI 识别结果、置信度、请求时间和必要技术元数据；不保存 HealthKit 运动、心率或健康明细数据。
- 保留周期：默认不超过 180 天，超期后按批次删除或匿名化处理。
- 删除机制：用户可通过隐私政策/支持邮箱申请删除服务端照片和分析记录；App 内删除摄入/任务会删除本地照片。
- App Store 声明：隐私政策和 App Store Connect 隐私标签必须声明照片会上传 AI 分析、可能保存到 Cloudflare R2、用途、保留周期和删除方式。

## Reviews 完成记录

| Review | 日期 | 结果 |
|--------|------|------|
| CEO/Founder Review | 2026-03-18 | 15 项决策，Watch-First 方向确认 |
| Eng Review | 2026-03-18 | 9 项技术修正 |
| Design Review | 2026-03-20 | 7 项方案 B 设计决策 |
| 代码审计 | 2026-03-24 | P1×2 P2×2 P3×1，全部修复 |
