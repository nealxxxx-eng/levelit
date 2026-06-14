# 磨平 LevelIt — CHANGELOG

## [0.6.0] - 2026-06 — 账号体系与社交 PK

> 详见 `磨平App_账号与社交PK_v0.6.0.md`、上架清单见 `AppStore上架准备清单_v1.0.md`。

### 新增功能
- **独立账号体系**：邮箱/手机号 + 密码注册登录，JWT（30 天）会话；档案/磨平数据云端同步、换机恢复；界面文案与服务商解耦。
- **注册体验**：年龄/身高/体重改三列滚轮选择器；分步页改 `ZStack+switch` 消除预渲染卡顿。
- **朋友 PK 五路配对**：服务端邀请码、唯一 username 搜索加好友、定向好友挑战（对方「接受」）、发榜广场（任何人认领，自己发的标「我发布的」）。
- **排行榜**：按 PK 胜场 + 累计消耗排名，高亮本人。
- **挑战生命周期管理**：待认领前可编辑/撤回/删除/重分享；行内 ••• 菜单（替代在 ScrollView 中失效的 swipe）。

### 后端
- `levelit-proxy`（80）catch-all 转发 `/api/*` 到 auth backend（3000）；新增 `api/social.js`、`api/users-store.js`。
- 新端点：`/api/auth/username`、`/api/users/search`、`/api/friends/*`、`/api/pk/board`、`/api/pk/challenges/:id/accept`、`/api/leaderboard`。
- 部署脚本复用已有 secret（不再每次部署登出全员）。

### 安全加固（审计 #2、#4–#10）
- AI 端点加鉴权（委托 `/api/auth/me`）；token 迁 Keychain；PK 进度防作弊限速；deviceToken 64-hex 校验；账号枚举中性化；响应不泄露内部 userId；输入有限数校验。

### 修复
- 邀请码两端不一致导致认领永远失败（改用服务端邀请码）。
- PK 页真机卡死：杜绝后台线程访问 SwiftData @Model；SwiftData 迁移兜底删除 `.store/-wal/-shm` 重建。
- 离线被误登出：仅 `missingSession`/HTTP 401 才登出。

### 待办（上架前）
- **#1 全程 HTTPS**（密码/照片/好友关系仍走明文）、#3 接口限流、应用内删除账号、加密合规声明。

## [0.5.0] - 2026-05-10 — 食物摄入与餐次管理体系

### 新增功能

#### 餐次智能分流
- 拍照后按"时段（早/午/晚/加餐）+ 配额（TDEE × 25/35/30/10）+ ±10% 容差"判定
- 加餐 → 直接进磨平任务流（行为同 v0.4）
- 正餐达标/欠摄 → Alert 提示后自动 popToRoot 回首页
- 正餐超标 → 进入新页面 `MealOverConfirmView` 确认热量缺口（Slider + 4 个快捷按钮）
- 同餐多张照片自动累加：第二张鸡蛋叠加第一张奶茶后判定，触发时显示分解

#### MealIntake 全口径记录
- 新增 `MealIntake @Model`：每次拍照都入库（达标/超标/欠摄/加餐 全部记录）
- `MealIntakeAggregator` 纯函数：`cumulativeKcal` / `dailyTotalKcal`
- `MealVerdictKind` 简化标签持久化（normal/over/under/snack），便于 SwiftData 序列化
- DebtTask 通过 `debtTaskId` 关联到对应 MealIntake，建立 1-1 关系

#### 实际摄入量调整（拍照前后）
- AnalysisView 加 Slider 10-100% + 4 个快捷按钮（全吃/3-4/一半/一口），与分餐功能正交
- 事后编辑：MealIntakeEditView 改食物名/餐次/卡路里
- 关联磨平任务（created/synced 状态）改 kcal 时弹 Alert 询问"是否同步任务"
- 已开始/已完成的任务保持账本完整性，不允许编辑联动

#### 主页与历史可见性
- HomeView 统计栏从 3 格扩到 4 格："今日摄入 / 今日结清 / 连续磨平 / 当前徽章"
- HomeView 主页加"今日摄入"快速预览卡片（最近 3 条 + 查看全部）
- TodayView 数据源全面切换到 MealIntake（含未生成磨平任务的）
- 删除入口三种方式：长按 / 右滑 / 编辑页按钮

#### 配置入口
- `MealQuotaConfigView`：用户可编辑三餐时间窗口、偏差容差，含实时判定预览、时序校验
- 入口在 HomeView toolbar 齿轮图标
- 默认窗口拓宽（贴近真实生活习惯）：早 06:00-10:30 / 午 11:00-14:00 / 晚 17:00-20:30

#### 异常日记录
- 新增 `AnomalyLog @Model`：reasonTags（出差/聚餐/生病/情绪化进食/节日庆祝/熬夜/其他）+ freeReason + dispositionPlan
- 入口 1：StatsView 顶部"异常日记录"卡片 → 历史列表
- 入口 2：StatsView 柱状图选中某天后弹"标记/编辑本日异常"按钮
- 同日唯一记录（再次进入自动编辑模式）
- StatsView 柱状图叠加 ⚠️ 标记异常日，标题旁"含 N 天异常"

#### Stats 数据源迁移
- StatsView 摄入数据全面切到 MealIntake（环形图 / 柱状图 / 趋势图）
- 修复历史 bug：之前用 DebtTask 算摄入会漏掉所有"达标/欠摄"食物

#### Watch 端今日摄入显示
- iPhone 端在 MealIntake CRUD 时通过 WC `applicationContext` 推送摘要
- Watch 新增 `WatchTodayIntakeStore`：UserDefaults 持久化 + 跨日清零
- WatchTaskInbox 顶部紧凑卡片"🍴 今日摄入 X kcal · N 条"
- 不在 Watch 存 MealIntake 数据库（保持 Watch 轻量定位）

### Bug Fixes
- **早餐窗口过窄** (#bug1)：默认窗口从 06:00–09:30 拓宽到 06:00–10:30，避免"10 点的早餐被算成加餐"
- **Alert 闭环缺失** (#bug2)：正餐达标/偏少 Alert 关闭后用户停留原页，按钮还能点 → 循环写入。修复：dismiss 自动 popToRoot；按钮 `hasClassified` 后锁住
- **Watch 删除闪退** (#bug3)：iPhone 删任务同步到 Watch 时 SwiftData `@Model` invalidate + ForEach 用 PersistentIdentifier diff 闪退。修复：所有 SwiftData ForEach 显式 `id: \.id`；handleDeleteTask 先广播 NotificationCenter 通知 + 50ms 延迟后再 delete，UI 先 popToRoot

### 改动概览
- 新增模型：`MealKind`、`MealQuotaConfig`、`MealClassifier`、`MealVerdict`、`MealIntake`、`MealIntakeAggregator`、`MealVerdictKind`、`AnomalyLog`、`AnomalyReasonTag`
- `UserProfile` 加 `tdee`（活动系数 1.2 / 1.375 / 1.55 / 1.725 业内标准）
- `WCMessageType.intakeSummary` + `WCPayloadKey.todayIntakeKcal/Count`
- 新路由：`mealOverConfirm`、`mealQuotaConfig`、`mealIntakeEdit`、`anomalyLogForm`、`anomalyLogList`
- 新视图：MealOverConfirmView、MealQuotaConfigView、MealIntakeEditView、AnomalyLogFormView、AnomalyLogListView、WatchTodayIntakeStore
- 防御性：所有 SwiftData @Model 的 ForEach 强制显式 `id: \.id`

### 测试
- 新增 36 个单测：`MealClassifierTests`(15) / `MealQuotaConfigTests`(13) / `MealIntakeAggregatorTests`(8)
- 含 1 个回归测试钉住 09:40 / 280 kcal 早餐场景
- 全套 147 / 147 通过；iPhone + watchOS scheme 双端编译干净

## [0.4.2] - 2026-05-06 — AI 代理迁移到阿里云 + 切换 Kimi-K2.5

### 后端代理迁移
- 主代理从 Vercel 迁移到阿里云 ECS 北京（`http://39.105.196.84`）
- 解决大陆访问 `*.vercel.app` 子域名 DNS 污染导致的 40s+ 超时问题
- 部署：Ubuntu 24.04 + Node 22 + systemd 守护，端口 80
- 新增 `server.js` 独立 HTTP 服务，提取 `api/analyze-core.js` 共享纯逻辑
- Vercel handler `api/analyze.js` 重构为引用 analyze-core，作为应急 fallback

### AI 模型变更
- 视觉模型从 `qwen3.5-plus` 切换到 `kimi-k2.5`（同一 DashScope Anthropic 兼容端点）
- 上游超时阈值从硬编码 8s 放宽为 30s（ECS 无 10s 函数级硬限制）

### iOS App
- `FoodAnalysisService.swift:6` endpoint 切换到 `http://39.105.196.84/api/analyze`
- `Info.plist` 为该 IP 添加 NSExceptionAllowsInsecureHTTPLoads 例外
- 已知遗留：上 App Store 前需补自签 TLS / 域名

## [0.4.1] - 2026-03-24 — 上架准备 + HealthKit 导入 + R2 数据存储

### 清理
- 删除 iPhone HomeView 测试工具（创建10kcal任务 / 清除所有数据）
- 删除 Watch WatchTaskInboxView 测试工具（10kcal快速测试 / 清除所有数据）
- 移除 FoodAnalysisService 中的 [FoodAI] 调试日志

### 隐私政策
- 新增 Vercel 隐私政策页面: https://levelit-proxy.vercel.app/privacy
- 覆盖相机权限、AI 照片分析、HealthKit 数据、本地存储声明
- 新增文件: `api/privacy.js`

### 深色模式适配
- 全面扫描 26 个视图文件，整体适配率 95%+
- 修复 FoodWallView / FoodDetailView 盘子边框白色渐变在深色模式下过亮
- 渐变色从 `.white.opacity(0.9)` 改为 `Color(.systemGray4)` 自动适应

### HealthKit 外部运动导入
- iPhone 端读取 HealthKit 今日运动记录（跑步、骑行、游泳等）
- 自动排除本 App 产生的运动（通过 bundleIdentifier 过滤）
- 首页显示"今日已运动 XX kcal"提示卡片，点击进入导入页
- 导入页展示所有外部运动详情（来源 App、时长、消耗）
- 用户选择分配给哪个待磨平任务，一键抵扣
- 抵扣后自动判断是否结清任务
- iPhone 新增 HealthKit 读取权限（entitlements + Info.plist）

### 每日 3 次本地通知
- 早 8 点 / 中午 12 点 / 晚 8 点提醒用户查看运动和磨平进度
- App 启动时自动请求通知权限并调度
- 有运动记录时提醒抵扣，无运动时提醒去运动

### 今日汇总页 + 朋友 PK 预留
- 首页右上角太阳按钮 + 左滑手势进入今日页
- 状态表情（根据收支动态变化）+ 收支对比
- 今日食物清单（摄入/消耗/完成状态）
- 今日指标：食物数、已结清、运动时长
- 朋友 PK 模块（即将上线）：对赌模式、排行榜、互相监督

### 运动数据统计分析页
- 首页左上角图表按钮 + 右滑手势进入统计页
- 周/月 Tab 切换
- 热量收支对比（摄入 vs 消耗 + 差值 + 进度条）
- 关键指标：任务数、已结清、完成率、运动时长
- 每日趋势柱状图（摄入/消耗双柱对比）
- 常用运动 Top 3 排行

### 任务手动删除 + Watch 同步
- 历史任务列表支持左滑删除（已完成 / 待完成均可删）
- 删除前弹出确认对话框，防止误操作
- 删除时自动清理本地食物照片
- 通过 WatchConnectivity 同步删除到 Watch 端
- 新增 `task_delete` 消息类型

### R2 数据存储
- AI 识别的图片和结果自动保存到 Cloudflare R2 (levelit-data bucket)
- 按日期分目录：`2026-03-24/{timestamp}_{foodName}.jpg` + `.json`
- 用于后续模型训练和热量估算调整
- 存储失败不影响主流程，静默降级

### 心率显示修复
- 修复心率始终为 "--" 的问题：`typesToShare` 缺少 `.heartRate`，导致 builder.statistics 不返回心率数据
- 显式 `dataSource.enableCollection(for: heartRate)` 确保传感器激活
- 心率显示增大至 20pt，位于进度环上方

### 运动模式常用置顶
- iPhone / Watch 运动模式选择页，根据历史任务统计使用频率
- 使用过 3 种以上不同模式时，最常用的 3 种自动置顶并显示"常用"标签
- 不足 3 种时保持默认排序（户外快走/跑走结合/户外跑步）

### HealthKit Info.plist 修复
- 创建独立的 `LevelItWatch Watch App/Info.plist`，直接声明 NSHealthShareUsageDescription / NSHealthUpdateUsageDescription
- 移除 pbxproj 中不可靠的 INFOPLIST_KEY_NSHealth* 条目
- 删除错误的 `INFOPLIST_KEY_NSHealthUpdateUsageDescription1`（无效 key）
- 删除不需要的 `INFOPLIST_KEY_NSHealthClinicalHealthRecordsShareUsageDescription`

---

## [0.4.0] - 2026-03-23 — AI 食物识别 + 美食墙

### 美食墙 (Food Wall)
- 首页右上角入口，展示所有拍过的食物照片
- 双 Tab：进行中 / 已结清
- 餐盘式布局：食物照片圆形裁切放在立体白瓷盘上，阴影+边缘高光
- 点击盘子进入详情：大盘展示 + 食物信息 + 运动记录（消耗/时长/完成度）
- 已结清任务带绿色勾标记
- 拍照 AI 识别成功后缩略图飞入动画

### 拍照落盘
- 拍照后自动保存到 Documents/FoodImages/{taskId}.jpg
- FoodImageStore 管理保存/读取/删除
- DebtTask.foodImageFileName 正式启用

### AI 拍照识别食物热量
- 拍照后调用 Qwen3.5-Plus Vision API 自动识别食物/饮料名称、emoji、热量
- Vercel Serverless 中转代理（香港节点），API Key 不暴露在客户端
- DashScope Anthropic 兼容接口，Thinking 模式关闭，响应 3-6 秒
- 图片自动压缩到 512px + JPEG 0.7 质量，节省传输和 token
- 低置信度（<0.3）判定为非食物，提示用户
- 识别失败时弹出 Alert：可重试或手动选择

### 新增文件
- `LevelIt/Services/FoodAnalysisService.swift` — iOS 端图片压缩、API 调用、结果解析
- `~/CC/levelit-proxy/` — Vercel 中转代理项目（api/analyze.js）

### 修改文件
- `ScanView.swift` — captureAndAnalyze() 从 mock 替换为真实 AI 调用，新增错误处理 Alert

## [0.3.0] - 2026-03-20 — Phase 3 + 方案 B + 运动模式扩展

### HealthKit 真实运动数据 (Phase 3)
- Watch 端集成 HKWorkoutSession + HKLiveWorkoutBuilder
- 支持 12 种 Apple 原生运动类型，运动记录自动同步到健康 App
- 心率实时显示（红色心形图标）
- HealthKit 授权流程（首次运动时弹出，拒绝则降级 Mock）
- 预热期间保守估算卡路里（2 kcal/min），真实数据到达后平滑切换
- 30 秒无 HealthKit 数据时提示"切换到模拟模式"

### Watch-First 方案 B 设计改造
- iPhone 创建任务后进入"已发送到手表"引导页（不再进入运动页）
- iPhone 任务详情智能分流：等待→引导、运动中→只读监控、已暂停→Watch 引导、已完成→结果页、无 Watch→降级模拟
- iPhone 降级模拟模式仅在无 Watch 配对时启用（WCSession.isPaired 判断）
- iPhone 监控模式纯只读，运动控制权完全在 Watch
- Watch 断连检测（60 秒无更新显示提示）
- Watch 结清时 iPhone 首页弹出"已结清"通知卡片

### 运动模式扩展 (3→12 种)
- 新增：室内步行、室内跑步、户外骑行、室内单车、椭圆机、划船机、核心训练、自由训练、泳池游泳
- 每种对应正确的 HKWorkoutActivityType + 室内/户外自动判断
- iPhone 模式选择页：基础 3 种 + "更多运动类型"展开
- Watch 快速接单时可选运动类型（强度点 + 预计时长 + 室内标签）
- iPhone 创建的任务到 Watch 后跳过模式选择（已在 iPhone 选过）

### Watch 新任务通知
- iPhone 创建任务同步到 Watch 时震动 + 弹出通知卡片
- 通知卡片显示食物 emoji/名称/热量 + "来自 iPhone 的任务"
- "开始磨平"直接进入运动 / "稍后再说"留在收件箱

### Bug Fixes
- Watch 导航重构：NavigationPath 统一管理，完成后可靠回到收件箱
- 暂停/恢复状态实时同步到 iPhone（togglePause 加 WC sendStatusUpdate）
- 暂停后恢复进度不清零（calorieOffset + durationOffset 偏移量机制）
- 部分完成正确显示"已磨平 XX%"（不再误显"已结清"）
- isFullyComplete 多条件判断（calories/percent/status 任一满足）
- "继续磨平"按钮文字（非首次运动时替代"开始磨平"）
- HealthKit 降级到 Mock 时预设已有进度
- hasWatch 检查加 activationState 判断
- finishWorkout 停止前先同步最新数据
- 结清通知 completedAt 字段同步修复
- 进度同步双通道（sendMessage 实时 + applicationContext + transferUserInfo 每 30 秒）

---

## [0.2.0] - 2026-03-19 — Phase 2: WC 同步

### WatchConnectivity 三层同步
- iPhone WCSyncService + Watch WatchSyncReceiver
- transferUserInfo 可靠队列（任务创建/状态变更）
- sendMessage 实时推送（双方前台时）
- updateApplicationContext（运动进度）
- 消息队列 + session 激活后补发
- 时间戳去重机制

### 持久化
- TaskExpiryService（48h 自动过期检查）
- App 启动时自动检查过期任务

---

## [0.1.0] - 2026-03-18 — Phase 1: UI 骨架 + Mock

### LevelItShared Swift Package
- DebtTask @Model（核心任务模型，含运动进度字段 + WC 序列化）
- 5 个枚举：DebtType, TaskLevel, TaskMode, TaskStatus, TaskSource
- PresetFood struct + PresetFoodLibrary（46 种预置食物）
- Achievement @Model + AchievementType（连续磨平徽章 3/7/14/30 天）
- UserStats @Model（用户统计，Streak 计算）
- TaskStateMachine（8 状态合法转换表）
- CalorieCalculator（12 种模式换算 + 热量校验）
- MotivationalQuotes（50 条励志文案，4 阶段）
- AppConstants（全局常量）

### iPhone App (9 页面)
- HomeView：今日欠债 + 统计栏 + CTA + 待磨平列表 + 空状态
- ScanView：真实相机预览 + 拍照（CameraPreview + CameraManager）
- ManualSelectView：预置食物库 + 分类筛选 + 搜索 + 自定义 kcal
- AnalysisView：食物分析结果 + 等级 + 三模式预览
- TaskModeView：12 种运动模式选择（基础 3 种 + 更多展开）
- TaskCreatedView："已发送到手表"引导页
- TaskDetailView：智能分流（监控/等待/降级/结果）
- TaskProgressView：降级模拟运动（MockWorkoutService）
- ResultView：结清动画 + 超额彩蛋 + 徽章 + 分享入口
- ShareCardView：分享卡渲染 + 系统分享面板
- TaskListView：历史任务（日期分组 + 状态筛选）

### Watch App (4 页面 + Complication)
- WatchTaskInboxView：收件箱 + 快速接单 + 新任务通知
- WatchQuickAddView：8 种常见食物 + Digital Crown 自定义 + 运动模式选择
- WatchWorkoutView：进度环 + Haptic + 励志文案 + HealthKit/Mock 双模式
- WatchCompletionView：结清/部分完成/超额 + 徽章
- DebtComplicationProvider：WidgetKit 表盘（circular/corner/rectangular）

### 测试
- 111 个自动化测试（10 个 Suite），全部通过
- 80+ 手动测试用例文档
