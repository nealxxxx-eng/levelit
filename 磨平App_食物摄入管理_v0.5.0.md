# 磨平 LevelIt — 食物摄入与餐次管理体系 v0.5.0

> 阶段性工作文档
> 生成日期: 2026-05-10
> 项目路径: ~/CC/levelit/

---

## 一、阶段目标

在 v0.4 的"拍照→AI 识别→生成磨平任务"主链路上，**引入"摄入"独立维度**，让用户：

1. 不是每张照片都需要还债（达标的不需要、偏少的不需要、加餐总是需要、超标按缺口需要）
2. 同一餐多张照片智能累加（午餐拍奶茶 + 鸡蛋 + 油条三张）
3. 所有摄入都有完整可见的历史与编辑能力
4. 主观可标记某天为"异常日"留作分析

这一阶段从纯"债务管理"扩展为完整的"摄入 + 还债"体系。

---

## 二、用户痛点 → 解决映射

| # | 用户反馈 | 修复 Step |
|---|---|---|
| 1 | "10 点拍的面包不该算加餐" | Step 2.5 默认窗口拓宽 + MealQuotaConfigView 配置入口 |
| 2 | "Alert 关闭还能再点 → 循环写入" | Step 4 Alert 后自动 popToRoot + hasClassified 锁按钮 |
| 3 | "看不到摄入历史" | Step 3 TodayView + Step 4c HomeView 主页预览 |
| 4 | "不能调整实际摄入量" | Step 4a 拍照时 Slider + Step 4b 事后编辑 |
| 5 | "同一餐多张照片应累加" | Step 3a/3b MealIntake + Aggregator + cumulativeKcal API |
| 6 | "未进任务的食物应有日志" | Step 3 MealIntake 全口径记录 |
| 7 | "Watch 删除任务后闪退" | Step 9 ForEach id + 主动通知 popToRoot |

---

## 三、数据模型新增

### 三个 @Model 新增

```
┌─────────────────────────┐         ┌──────────────────────┐
│      MealIntake         │ ───────▶│      DebtTask        │
│  (摄入事实，每张照片)    │   debt  │  (磨平任务，仅必要时) │
│                         │ TaskId  │                      │
│ • foodName/Emoji        │         │ • estimatedCalories  │
│ • estimatedCalories     │         │ • taskMode           │
│ • originalCalories      │         │ • status (8-state    │
│ • diners                │         │   FSM 不变)          │
│ • foodImageFileName     │         │ • burnedCalories     │
│ • takenAt               │         │ • progressPercent    │
│ • mealKind              │         │   ...                │
│ • verdictKind ←─ 简化   │         └──────────────────────┘
│ • debtTaskId? ─────┐    │
└────────────────────┼────┘
                     │
                     ▼
                关联（1-1，可选）

┌─────────────────────────┐
│      AnomalyLog         │
│  (用户主观标记某天异常)  │
│                         │
│ • date (startOfDay)     │
│ • reasonTags []         │
│ • freeReason            │
│ • dispositionPlan       │
│ • createdAt / updatedAt │
└─────────────────────────┘
```

### 配置类型（值类型 + UserDefaults）

- `MealKind`：早/午/晚/加餐 枚举（含默认时间窗 + 默认配额比例）
- `MealQuotaConfig`：用户可覆写的窗口/比例/容差，UserDefaults 持久化
- `MealVerdict`：分类结果（关联值枚举）+ `MealVerdictKind`（简化标签）
- `MealClassifier`：纯函数，根据时间和卡路里返回 verdict
- `MealIntakeAggregator`：纯函数聚合器（同餐累加 / 当日总和）

---

## 四、关键设计决策

### D1 — 为什么 MealIntake 独立于 DebtTask
**问题**：能不能直接扩展 DebtTask 加个"达标无需还债"状态？
**答**：不能。DebtTask 有 8 状态 FSM 严格约束，加新状态会破坏现有同步逻辑。摄入和还债是不同维度（摄入是事实，还债是行为），独立解耦更清晰。

### D2 — TDEE 系数（业内标准）vs allowanceRate（自定义 7-16%）
**为什么不复用现有 dailyAllowance**：
- `dailyAllowance` 是"每日自然消耗的额外余额"（BMR × 7-16%），用于"运动消耗的兜底"
- 三餐配额的基准应是 TDEE（每日总能量消耗）
- 因此新加 `tdeeMultiplier`（1.2 / 1.375 / 1.55 / 1.725 业内通用），不破坏旧字段

### D3 — 每张照片独立判定 vs 同餐累加
**选累加**。但通过参数化设计兼容两种：`MealClassifier.classify(kcal:)` 是单张版本，`classify(cumulativeKcal:)` 是累加版本。AnalysisView 默认走累加路径，调用方负责传入累计值。

### D4 — `MealVerdict`（关联值）vs `MealVerdictKind`（简化标签）
- `MealVerdict` 是分类逻辑的输出，含 actual / quota / gap 等数据
- `MealVerdictKind` 是持久化用的 String enum，便于 SwiftData 序列化和 SwiftUI .alert(item:)
- 转换方向：单向 `MealVerdict.kind → MealVerdictKind`

### D5 — 配置覆写（方案 B）vs 放宽默认值（方案 A）
**A+B 都做**：
- 默认窗口放宽（覆盖 90% 用户）
- MealQuotaConfigView 给个性化场景兜底（夜班、跨时区、孕期等）

### D6 — Watch 端不存 MealIntake 数据库
**只镜像总数**：Watch 通过 WC `applicationContext` 接收 iPhone 推送的 `todayIntakeKcal` + `todayIntakeCount`，存 UserDefaults。
- 优点：不破坏 Watch 现有 ModelContainer / 不做大量 WC 同步 / 屏幕小不适合详情列表
- 缺点：Watch 端无法独立查询；这与 Watch-First 的"运动执行端"定位一致

### D7 — 关联任务编辑同步策略
- 仅 `created/synced` 状态的 DebtTask 允许"同步改 kcal"（弹 Alert 让用户选）
- `inProgress/paused/settled/completed/cancelled/expired` 状态视为"账本锁定"，编辑摄入不影响任务
- 删除摄入时联级删除活跃任务（已结清的不动，保留账本完整性）

---

## 五、UX 流（端到端）

### 流 1：早餐拍照（达标场景）
```
HomeView → 拍一下 → ScanView 拍照 →
FoodAnalysisService 上传 → AnalysisView：
  · 显示热量 / 分餐 Slider / 实际摄入 Slider
  · 用户调到 50% → 大数字实时变
  · 点"生成磨平任务" → MealClassifier.classify
  · normalMeal → 弹 Alert「☀️ 本餐午餐达标 / 本餐合计 580 kcal」
  · 点"好的" → popToRoot 回首页
HomeView：
  · 「今日摄入」格 = 580
  · 「今日摄入」预览卡片显示该条
TodayView：
  · 详细列表，绿色「达标」tag
StatsView：
  · 柱状图反映 580 kcal 摄入（无论是否生成 task）
```

### 流 2：午餐三张累加触发缺口
```
12:00 拍奶茶 280 → AnalysisView → underMeal Alert → popToRoot
  · MealIntake#1 入库（verdict=under）
12:15 拍鸡蛋 250 → cumulative = 280+250 = 530 → normalMeal → Alert
  · MealIntake#2 入库（verdict=normal）
12:30 拍油条 200 → cumulative = 730 → overMeal gap=7
  · MealIntake#3 入库（verdict=over）
  · push MealOverConfirmView：
    顶部 banner「之前 530 + 本张 200 = 累计 730」
    Slider 调整缺口 0..730 默认 7
  · 用户确认 → push TaskMode → 选模式 → 创建 DebtTask
  · MealIntake#3.debtTaskId 回填
TodayView：
  · 3 条记录（绿/橙/红 tag）
  · MealIntake#3 显示活跃任务图标
```

### 流 3：事后调整摄入
```
TodayView 点击某条 → MealIntakeEditView：
  · 改食物名 / 餐次 / kcal Slider+Stepper
  · "实际摄入热量"区显示与原始识别的差异（绿/红）
  · 关联未结清任务 → 显示锁定 banner（不可同步）
  · 关联 created/synced 任务 → 保存时弹 Alert：
      "同步改任务 / 仅改摄入 / 取消"
  · 删除按钮联级处理活跃任务 + 照片
```

### 流 4：异常日记录
```
StatsView →（任一）：
  A) 顶部「异常日记录」卡片 → AnomalyLogListView 历史浏览
  B) 选中柱状图某天 → 下方"标记/编辑本日异常"按钮
  → AnomalyLogForm：
    · 多选 chip：✈️出差 / 🍽️聚餐 / 🤒生病 / 😞情绪化进食 / 🎉节日庆祝 / 🌙熬夜 / 🏷️其他
    · 自由原因 TextField
    · 处置方案 TextField（如"明天加 30 分钟有氧"）
StatsView：
  · 柱状图自动叠加 ⚠️ 标记
  · 标题旁"含 N 天异常"
```

### 流 5：Watch 端摄入同步
```
[iPhone]                         [Watch]
AnalysisView 写 MealIntake       
  ↓
WCSyncService.pushTodayIntakeContext
  → updateApplicationContext
    {todayIntakeKcal: 730,
     todayIntakeCount: 3}     ─→  didReceiveApplicationContext
                                  → routeMessage handleIntakeSummary
                                    → WatchTodayIntakeStore.update
                                      → @Published 触发刷新
                                        → WatchTaskInbox 顶部
                                          「🍴 今日摄入 730 kcal · 3」
```

---

## 六、测试覆盖

### 新增单测（36 个）

| Suite | 用例数 | 覆盖 |
|---|---|---|
| MealClassifierTests | 15 | 时间窗边界 / ±10% 容差临界 / nil profile 兜底 / 累加场景 / 0 容差边界 / 09:40 回归测试 / 等 |
| MealQuotaConfigTests | 13 | 默认值合理性 / TDEE × 比例 / 时间归类 / UserDefaults 往返 / 边界（10:30/14:00 右开区间） |
| MealIntakeAggregatorTests | 8 | 同餐累加 / 跨日不累加 / 不同 kind 不混 / 负 kcal 钳到 0 / 与 MealClassifier 集成 |

### 全套测试结果
```
Test run with 147 tests in 13 suites passed
```

### 系统测试
- ✅ iPhone scheme 编译成功（iPhone 17 simulator）
- ✅ watchOS scheme 编译成功（generic/platform=watchOS）
- ⚠️ 仅 3 个历史 warning（FoodWall / WCSync 异步 lock，与本阶段无关）

### 手测验证场景
1. ✅ 09:40 拍 280K 面包 → Alert "早餐偏少" → popToRoot（v0.5.0 早餐拓宽到 10:30）
2. ✅ 12:00 拍奶茶 → 12:15 拍鸡蛋 → 12:30 拍油条 → 第三张触发缺口确认页
3. ✅ TodayView 长按 / 右滑删除条目
4. ✅ HomeView 主页"今日摄入"卡片实时刷新
5. ✅ MealQuotaConfigView 改时间窗实时预览
6. ✅ StatsView 柱状图异常日 ⚠️ 标记
7. ✅ iPhone 删任务 → Watch 不闪退（修复 #bug3）

---

## 七、文件清单

### 新增文件（11 个）

```
LevelItShared/Sources/Models/
├── MealKind.swift                      # 餐次枚举 + 时间窗
├── MealQuotaConfig.swift               # 配置 + UserDefaults 持久化
├── MealIntake.swift                    # @Model + MealVerdictKind
└── AnomalyLog.swift                    # @Model + AnomalyReasonTag

LevelItShared/Sources/StateMachine/
├── MealClassifier.swift                # 纯函数分类器
└── MealIntakeAggregator.swift          # 累加聚合器

LevelItShared/Tests/
├── MealClassifierTests.swift           # 15 用例
├── MealQuotaConfigTests.swift          # 13 用例
└── MealIntakeAggregatorTests.swift     # 8 用例

LevelIt/LevelIt/Features/MealVerdict/
└── MealOverConfirmView.swift           # 缺口确认页

LevelIt/LevelIt/Features/Settings/
└── MealQuotaConfigView.swift           # 餐次配置编辑

LevelIt/LevelIt/Features/Today/
└── MealIntakeEditView.swift            # 摄入编辑表单

LevelIt/LevelIt/Features/Stats/
├── AnomalyLogFormView.swift            # 异常日表单
└── AnomalyLogListView.swift            # 异常日列表

LevelItWatch Watch App/Services/
└── WatchTodayIntakeStore.swift         # ObservableObject 缓存
```

### 修改文件（关键）
```
LevelItShared/Sources/Models/UserProfile.swift          # +tdee
LevelItShared/Sources/Constants/AppConstants.swift      # +intakeSummary / payload keys
LevelIt/LevelIt/LevelItApp.swift                        # ModelContainer +MealIntake / +AnomalyLog
LevelIt/LevelIt/Core/AppRouter.swift                    # +5 个新路由
LevelIt/LevelIt/ContentView.swift                       # 路由分发
LevelIt/LevelIt/Features/Home/HomeView.swift            # statsRow 4 格 + 摄入卡片 + toolbar 齿轮
LevelIt/LevelIt/Features/Today/TodayView.swift          # 数据源切到 MealIntake
LevelIt/LevelIt/Features/Stats/StatsView.swift          # 数据源切换 + 异常日入口 + ⚠️ 叠加
LevelIt/LevelIt/Features/Analysis/AnalysisView.swift    # 实际摄入 Slider + 餐次分流 + 写入 MealIntake
LevelIt/LevelIt/Features/TaskMode/TaskModeView.swift    # 接 intakeId 回填
LevelIt/LevelIt/Services/WCSyncService.swift            # +pushTodayIntakeContext
LevelItWatch Watch App/Services/WatchSyncReceiver.swift # 接收 intakeSummary + 删除防闪退
LevelItWatch Watch App/Features/TaskInbox/WatchTaskInboxView.swift  # 摄入卡片 + 删除事件订阅
```

---

## 八、已知遗留 / 后续计划

### 已知遗留
- `MealClassifier` 的 cumulative API 已预留，但 AnalysisView 当前每次都重新查询。性能上可接受（每天 ~10 条），如未来记录变多可加缓存。
- `MealIntake` 删除时硬删（D4 决策），不进垃圾桶。
- 配额比例（25/35/30/10）暂不开放编辑，避免 3 个 Slider 联动复杂 UX。

### 后续候选
- **FoodWall 切到 MealIntake**：当前 FoodWall 基于 DebtTask，应同步切换以反映"达标/欠摄"的食物
- **异常日 vs 平日对比分析**：StatsView 加一个"平均日 vs 异常日"对比模块
- **同餐去重**：当前重复拍同一杯奶茶会重复记录；可加"基于 foodName + 5 分钟内"的软合并提示
- **Watch 摄入趋势 Complication**：表盘组件直接显示今日摄入数字
- **CloudKit 同步**：目前 MealIntake / AnomalyLog 仅本地，付费 Developer 账号到位后可启用

---

## 九、版本基线

- **iOS 17+** / **watchOS 10+**（与项目基线一致）
- **纯 Apple 框架**（无第三方依赖）
- **不向后兼容 v0.4 数据**：v0.4 升级到 v0.5 后历史 DebtTask 不会自动生成对应 MealIntake，TodayView 摄入列表对老数据为空（可接受 — 全口径统计从 v0.5 起）
