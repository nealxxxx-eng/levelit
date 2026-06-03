# 磨平 LevelIt — 项目总结 v0.4.1

> 生成日期: 2026-03-24
> 当前版本: v0.4.1
> 项目路径: ~/CC/levelit/

---

## 一、产品概述

**磨平 (LevelIt)** 是一款 iOS + Apple Watch 健康管理 App。核心理念：用户吃了高热量食物后，通过运动来"磨平"这笔热量债务。

### 核心流程
```
拍照/手动选食物 → AI 识别热量 → 生成磨平任务 → Apple Watch 运动 → HealthKit 记录 → 结清任务
```

### 平台
- iPhone App (iOS 18+)
- Apple Watch App (watchOS 26.2+)
- Vercel Serverless 中转代理 (香港节点)
- Cloudflare R2 数据存储

---

## 二、版本历史

| 版本 | 日期 | 里程碑 |
|------|------|--------|
| 0.1.0 | 2026-03-18 | UI 骨架 + Mock 数据 |
| 0.2.0 | 2026-03-19 | WatchConnectivity 三层同步 |
| 0.3.0 | 2026-03-20 | HealthKit 真实运动 + Watch-First 方案 B + 12 种运动模式 |
| 0.4.0 | 2026-03-23 | AI 食物识别 (Qwen3.5-Plus) + 美食墙 + 拍照落盘 |
| 0.4.1 | 2026-03-24 | 上架准备 + HealthKit 导入 + 统计分析 + R2 存储 |

---

## 三、技术架构

### 项目结构
```
~/CC/levelit/
├── LevelIt/                        # Xcode 项目
│   ├── LevelIt/                    # iPhone App (30 个 Swift 文件)
│   │   ├── Core/                   # 路由、设计系统、工具
│   │   │   ├── AppRouter.swift
│   │   │   ├── DesignTokens.swift
│   │   │   └── PopToRoot.swift
│   │   ├── Features/               # 功能页面
│   │   │   ├── Home/HomeView.swift           # 首页 (TabView 三页滑动)
│   │   │   ├── Stats/StatsView.swift         # 数据统计 (周/月)
│   │   │   ├── Today/TodayView.swift         # 今日汇总 + PK 预留
│   │   │   ├── Scan/ScanView.swift           # 拍照 + AI 识别
│   │   │   ├── FoodWall/FoodWallView.swift   # 美食墙
│   │   │   ├── FoodWall/FoodDetailView.swift # 食物详情
│   │   │   ├── Analysis/AnalysisView.swift   # AI 分析结果
│   │   │   ├── TaskMode/TaskModeView.swift   # 运动模式选择
│   │   │   ├── TaskCreated/                  # "已发送到手表"
│   │   │   ├── TaskDetail/                   # 任务智能分流
│   │   │   ├── Progress/                     # 降级模拟运动
│   │   │   ├── Result/                       # 结清结果 + 动画
│   │   │   ├── Share/                        # 分享卡
│   │   │   ├── TaskList/TaskListView.swift   # 历史任务
│   │   │   ├── ManualSelect/                 # 手动选食物
│   │   │   └── WorkoutImport/                # HealthKit 运动导入
│   │   ├── Services/                # 服务层
│   │   │   ├── FoodAnalysisService.swift     # AI 识别 API 客户端
│   │   │   ├── FoodImageStore.swift          # 食物照片本地存储
│   │   │   ├── HealthKitImportService.swift  # HealthKit 外部运动查询
│   │   │   ├── NotificationScheduler.swift   # 每日 3 次本地通知
│   │   │   ├── WCSyncService.swift           # WatchConnectivity (iPhone 端)
│   │   │   ├── MockWorkoutService.swift      # 降级模拟运动
│   │   │   └── TaskExpiryService.swift       # 48h 自动过期
│   │   ├── ContentView.swift        # 根视图 + 路由分发
│   │   ├── LevelItApp.swift         # App 入口
│   │   ├── LevelIt.entitlements     # HealthKit 能力
│   │   └── Info.plist
│   │
│   └── LevelItWatch Watch App/     # Watch App (12 个 Swift 文件)
│       ├── Features/
│       │   ├── TaskInbox/WatchTaskInboxView.swift    # 收件箱
│       │   ├── QuickAdd/WatchQuickAddView.swift      # 快速接单
│       │   ├── Workout/WatchWorkoutView.swift        # 运动界面 + 心率
│       │   ├── Workout/WatchWorkoutContainerView.swift
│       │   └── Completion/WatchCompletionView.swift
│       ├── Services/
│       │   ├── WatchHealthKitManager.swift   # HKWorkoutSession + 心率
│       │   ├── WatchSyncReceiver.swift       # WatchConnectivity (Watch 端)
│       │   ├── WatchMockWorkoutService.swift
│       │   └── WatchHapticManager.swift
│       ├── Complication/                     # 表盘组件
│       └── LevelItWatch Watch App.entitlements
│
├── LevelItShared/                   # Swift Package (共享模型)
│   └── Sources/
│       ├── Models/
│       │   ├── DebtTask.swift               # 核心任务模型 (@Model)
│       │   ├── TaskMode.swift               # 12 种运动模式
│       │   ├── TaskStatus.swift             # 8 种状态
│       │   ├── PresetFood.swift             # 46 种预置食物
│       │   ├── Achievement.swift            # 徽章系统
│       │   └── UserStats.swift              # 用户统计
│       ├── Logic/
│       │   ├── TaskStateMachine.swift       # 状态转换表
│       │   ├── CalorieCalculator.swift      # 热量换算
│       │   └── MotivationalQuotes.swift     # 50 条励志文案
│       └── Constants/AppConstants.swift
│
~/CC/levelit-proxy/                  # Vercel Serverless 中转代理
    ├── api/
    │   ├── analyze.js               # AI 识别 + R2 存储
    │   └── privacy.js               # 隐私政策页面
    ├── vercel.json                  # 路由 + 香港节点
    └── package.json                 # @aws-sdk/client-s3
```

### 技术栈
| 层级 | 技术 |
|------|------|
| UI | SwiftUI + SwiftData |
| 共享模型 | Swift Package (LevelItShared) |
| 设备间同步 | WatchConnectivity (三层: sendMessage + transferUserInfo + applicationContext) |
| 运动数据 | HealthKit (HKWorkoutSession + HKLiveWorkoutBuilder) |
| AI 识别 | Qwen3.5-Plus Vision (DashScope Coding Plan, Anthropic 兼容接口) |
| 中转代理 | Vercel Serverless Functions (香港节点 hkg1) |
| 数据存储 | Cloudflare R2 (levelit-data bucket, APAC) |
| 本地存储 | SwiftData + Documents/FoodImages/ |

---

## 四、功能清单

### iPhone App (15 个页面)

| 页面 | 功能 |
|------|------|
| **首页** (TabView 三页) | 左滑统计、中间首页、右滑今日 |
| **数据统计** | 周/月切换、热量收支、每日趋势柱状图、常用运动 Top 3 |
| **今日汇总** | 状态表情、收支对比、食物清单、朋友 PK 预留 |
| **拍照** | 真实相机 + AI 识别 + 飞入动画 |
| **手动选择** | 46 种预置食物 + 分类筛选 + 搜索 + 自定义 |
| **AI 分析结果** | 食物名/emoji/热量/等级 + 三模式预览 |
| **运动模式选择** | 12 种模式 + 常用 3 种置顶 |
| **已发送到手表** | Watch-First 引导页 |
| **任务详情** | 智能分流 (监控/等待/降级/结果) |
| **模拟运动** | 无 Watch 时降级模式 |
| **结清结果** | 动画 + 超额彩蛋 + 徽章 |
| **分享卡** | 渲染 + 系统分享 |
| **美食墙** | 餐盘布局 + 进行中/已结清 Tab + 长按删除 |
| **食物详情** | 大盘展示 + 运动记录 |
| **历史任务** | 日期分组 + 状态筛选 + 长按删除 |
| **运动导入** | HealthKit 外部运动 → 选择任务抵扣 |

### Watch App (5 个页面 + Complication)

| 页面 | 功能 |
|------|------|
| **收件箱** | 待磨平列表 + 快速接单 + iPhone 任务通知 |
| **快速接单** | 8 种常见食物 + Digital Crown 自定义 + 运动模式 (常用置顶) |
| **运动界面** | 进度环 + 心率 (20pt) + 卡路里 + 时长 + 励志文案 |
| **完成页** | 结清/部分完成/超额 + 徽章 |
| **表盘** | WidgetKit (circular/corner/rectangular) |

### 后端服务

| 服务 | 说明 |
|------|------|
| **AI 识别** | POST /api/analyze → Qwen3.5-Plus Vision → JSON 结果 |
| **R2 存储** | 每次识别自动保存图片 + 结果到 Cloudflare R2 |
| **隐私政策** | GET /privacy → 中文隐私政策 HTML 页面 |

---

## 五、关键配置

### 环境变量 (Vercel)
| 变量 | 用途 |
|------|------|
| DASHSCOPE_API_KEY | 通义千问 API 密钥 (sk-sp-*) |
| R2_ACCESS_KEY_ID | Cloudflare R2 访问密钥 |
| R2_SECRET_ACCESS_KEY | Cloudflare R2 秘密密钥 |
| R2_ENDPOINT | R2 S3 兼容端点 |
| R2_BUCKET_NAME | levelit-data |

### URL 端点
| 端点 | URL |
|------|-----|
| AI 识别 API | https://levelit-proxy.vercel.app/api/analyze |
| 隐私政策 | https://levelit-proxy.vercel.app/privacy |
| DashScope | https://coding.dashscope.aliyuncs.com/apps/anthropic/v1/messages |
| R2 存储 | https://6e312d49cdc620032842006e3869143f.r2.cloudflarestorage.com |

### 权限声明
| 权限 | 平台 | 用途 |
|------|------|------|
| NSCameraUsageDescription | iPhone | 拍摄食物照片 |
| NSPhotoLibraryAddUsageDescription | iPhone | 保存分享卡 |
| NSHealthShareUsageDescription | iPhone + Watch | 读取运动数据 |
| NSHealthUpdateUsageDescription | Watch | 记录运动数据 |
| 通知权限 | iPhone | 每日 3 次提醒 |

---

## 六、v0.4.1 本次开发内容 (2026-03-24)

### 新增功能 (11 项)
1. **清理测试工具** — 删除 iPhone/Watch 测试按钮和调试日志
2. **隐私政策页面** — Vercel 部署，覆盖相机/AI/HealthKit/通知
3. **深色模式适配** — 扫描 26 个视图，修复盘子边框渐变
4. **HealthKit Info.plist 修复** — 修正错误的 INFOPLIST_KEY
5. **运动模式常用置顶** — iPhone/Watch 根据历史频率排序 Top 3
6. **HealthKit 外部运动导入** — 检测今日外部运动，选择任务抵扣
7. **每日 3 次本地通知** — 早 8/午 12/晚 8 提醒
8. **心率显示修复** — typesToShare 加 heartRate，显式启用采集
9. **R2 数据存储** — AI 识别图片+结果自动保存到 Cloudflare R2
10. **任务手动删除** — 首页/历史/美食墙长按删除，Watch 同步
11. **统计分析页 + 今日汇总页** — TabView 三页滑动，周/月统计，朋友 PK 预留

### 新增文件 (9 个)
| 文件 | 说明 |
|------|------|
| `LevelIt.entitlements` | iPhone HealthKit 能力 |
| `HealthKitImportService.swift` | 查询今日外部运动 |
| `WorkoutImportView.swift` | 运动导入 UI |
| `NotificationScheduler.swift` | 本地通知调度 |
| `StatsView.swift` | 数据统计页 |
| `TodayView.swift` | 今日汇总页 |
| `api/privacy.js` | 隐私政策 |
| `api/r2test.js` | R2 调试 (已删除) |
| Watch `Info.plist` | HealthKit 描述 (后回退) |

### 修改文件 (15 个)
HomeView, TaskListView, FoodWallView, FoodDetailView, TaskModeView, WatchQuickAddView, WatchWorkoutView, WatchHealthKitManager, WatchSyncReceiver, WCSyncService, AppRouter, ContentView, LevelItApp, AppConstants, project.pbxproj

### Bug 修复 (3 个)
1. HealthKit 心率始终为 0 — typesToShare 缺 heartRate
2. Vercel 环境变量尾部换行符 — echo 改 printf
3. Watch 卡死 — 移除 .symbolEffect(.pulse, .repeating)

---

## 七、发布前待办

### 必须完成 (P0)
| 任务 | 状态 | 说明 |
|------|------|------|
| 付费 Apple Developer 账号 | 未完成 | 上架必须，$99/年 |
| App Icon + 启动屏 | 未完成 | 需设计 |
| App Store 截图 | 未完成 | iPhone + Watch 各 3 张 |
| TestFlight 内测 | 未完成 | 配置 + 邀请测试 |
| Session Recovery | 未完成 | Watch 崩溃恢复 |

### 可选优化 (P1-P2)
| 任务 | 优先级 |
|------|--------|
| DESIGN.md 设计系统 | P1 |
| 天气动态图标 | P2 |
| 食物"前科记录" | P2 |
| 周度"账单"报告 | P2 |
| 个性化热量换算 | P2 |

---

## 八、数据统计

| 指标 | 数值 |
|------|------|
| iPhone Swift 文件 | 30 个 |
| Watch Swift 文件 | 12 个 |
| 共享模型文件 | 10+ 个 |
| 自动化测试 | 111 个 |
| 预置食物 | 46 种 |
| 运动模式 | 12 种 |
| 励志文案 | 50 条 |
| 版本迭代 | 5 个 (v0.1 → v0.4.1) |
| 开发周期 | 7 天 (2026-03-18 ~ 03-24) |
