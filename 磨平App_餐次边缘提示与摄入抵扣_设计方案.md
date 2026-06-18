# 磨平 App — 餐次边缘提示 & 摄入抵扣磨平 设计方案

> 状态：**待评审**（先文档后实现）｜日期：2026-06-18
> 已确认决策：
> 1. 需求一边缘选"正餐"→ **记摄入、不生成磨平**（沿用现有正餐规则：达标不磨平、超标仍磨平）
> 2. 需求二抵扣入口 → **生成磨平任务并立即用今日运动抵扣**（够则直接结清）
> 3. 推进方式：先出本文档评审，再分任务实现

---

## 需求一：餐次时间段边缘提示

### 1.1 现状
`MealClassifier.mealKind(at:)` 是**硬边界**：拍照时间落在早/午/晚窗口内即正餐，否则加餐。无任何"边缘模糊"处理。`AnalysisView.classifyAndNavigate()` 直接 `classify → switch verdict` 分流。

### 1.2 边缘判定规则
- **边缘区**：任一正餐窗口（早/午/晚）的 `start` 或 `end` 边界 **±30 分钟**（阈值设为可配置常量 `edgeMinutes = 30`，放 `AppConstants`）。
- 落在边缘区时，给出**建议餐次**（距离最近的那个正餐窗口对应的 `MealKind`），让用户在「该正餐 / 加餐」之间二选一。
- 非边缘区：维持现有硬判定，无打扰。
- 例：午餐窗口 11:00–14:00 → 边缘区为 10:30–11:30 与 13:30–14:30；在这两段内拍照才提示。

### 1.3 模型改动（`LevelItShared`）
- `MealClassifier` 新增纯函数：
  ```swift
  /// date 处于某正餐窗口边界 ±edgeMinutes 内时，返回建议的正餐 kind；否则 nil。
  static func edgeSuggestion(at date:, config:, calendar:) -> MealKind?
  ```
- `MealClassifier.classify` 新增可选入参 `overrideKind: MealKind?`：当用户在边缘弹窗里做了选择，用强制 kind 跳过时段判定，复用既有 snack / normalMeal / overMeal / underMeal 全部逻辑（**不新增 verdict case**，把"是否边缘"留在 View 层判断，降低对现有 switch 的侵入）。
- 取舍说明：不新增 `MealVerdict.edgeAmbiguous` case，避免所有 `switch verdict` 的调用点都要改；边缘检测作为 classify **之前**的一步。

### 1.4 UI 流程（`AnalysisView`）
```
classifyAndNavigate():
  if let suggested = MealClassifier.edgeSuggestion(at: now, ...) {
      弹 confirmationDialog「这是加餐还是正餐？」
        ├─ 选「正餐(suggested)」→ classify(overrideKind: suggested) → 走正餐分支(记摄入,达标不磨平)
        └─ 选「加餐」          → classify(overrideKind: .snack)   → 走加餐分支(进磨平任务流)
  } else {
      原有 classify → switch（不变）
  }
```

### 1.5 文件清单（≤3 改动文件）
| 文件 | 改动 |
|------|------|
| `LevelItShared/.../MealClassifier.swift` | 加 `edgeSuggestion` + classify 的 `overrideKind` 参数 |
| `LevelItShared/.../Constants/AppConstants.swift` | 加 `mealEdgeMinutes = 30` |
| `LevelItShared/Tests/MealClassifierTests.swift` | 边缘判定 + override 的单测 |
| `LevelIt/.../Analysis/AnalysisView.swift` | 边缘 confirmationDialog + 二选一后重新分流 |

### 1.6 边界 & 测试用例
- 正好在边界点（如 14:00:00）；边界 ±30 分整点（13:30、14:30）的开闭区间。
- 两餐边缘区**重叠**（紧凑配置下，午餐 end 与晚餐 start ±30 交叠）→ 取最近边界的建议 kind。
- 早餐开始前更早时间（如 05:00）不在任何边缘区 → 不提示，纯加餐。
- 无 `UserProfile`（新用户）→ 仍按加餐，**不弹边缘提示**（避免无配额时无意义打扰）。
- override 为正餐时：达标→normalMeal、超标→overMeal、欠摄→underMeal 行为与时段内判定一致。

---

## 需求二：摄入编辑页「用今日运动抵扣磨平」

### 2.1 现状
`MealIntakeEditView` 有：食物名 / 餐次 / 热量 / 关联任务同步 / 删除。**没有**把一条"未磨平的摄入"转成磨平任务并用今日运动结算的入口。正餐达标、加餐缓冲内的摄入不会生成 `DebtTask`，用户无法主动磨平它。

### 2.2 入口与显示条件
- 在 `MealIntakeEditView` 新增一个 Section：**「用今日运动抵扣磨平」**。
- **显示条件**：该摄入当前**没有有效关联磨平任务**（`debtTaskId == nil`，或关联任务已是终态 cancelled/expired）。已在磨平流程中的摄入不显示（避免重复建任务）。
- 入口处展示预览：`目标 = 该摄入热量`、`今日可用运动余额 = X kcal`、抵扣后预计 `结清 / 还差 Y kcal`。

### 2.3 抵扣账本设计（核心，需评审）
**问题**：今日 HealthKit 运动消耗是"共享量"，不能被多条摄入重复抵扣。

**拟定口径**：
```
今日运动总消耗 E   = 今日 HealthKit 活动能量合计（活动能量口径，与 PK 修复后一致）
今日已抵扣 D       = Σ(今日各 DebtTask.burnedCalories)   // 已被运动还掉的债
可用余额 Avail     = max(0, E − D)
本次抵扣 offset    = min(intake.kcal, Avail)
```
新建 `DebtTask`(target = intake.kcal, mode 默认)：
- `burnedCalories = offset`
- `offset >= target` → 经 `TaskStateMachine.transition` 直接到 `settled`（结清）
- `0 < offset < target` → `inProgress`（部分还，余量待运动）
- `offset == 0`（今日无可用运动）→ `created`（等价于普通新建磨平任务）
- 回写 `intake.debtTaskId`，建立关联；同步 Watch（`WCSyncService`）。

**去重要点 / 风险（评审重点）**：
1. `E` 与 `D` 的口径必须一致：`D` 里的 `burnedCalories` 多来自 Watch 实测运动，这些运动**也在 HealthKit 的 `E` 里**——所以 `E − D` 才是"尚未对应到任何债务的净运动"，避免重复抵扣。需确认本 App 写入 HealthKit 的运动确实计入 `E`（否则 `E−D` 会偏大）。
2. **与 PK 的关系**：PK 进度用今日运动 `max(HealthKit, 账本)` 计分，是"比赛维度"，与"债务抵扣维度"相互独立、互不扣减——同一份运动既可推进 PK，也可抵扣债务，二者不冲突（PK 不是消耗账本）。本设计**不**改 PK。
3. **跨日**：`E`、`D` 只统计"今天"（自然日）；隔日打开编辑旧摄入时，可用余额按"那条摄入当天"还是"今天"？拟定：**按今天**（用户是"现在想用今天的运动抵扣"）。旧摄入跨日抵扣的语义列为开放问题。
4. **NaturalAllowance（每日自然消耗）**是否算进 `E`？拟定**不算**（自然消耗是"免费额度"，已在别处用于配额，不应再用于还债，否则双重计数）。

### 2.4 文件清单（≤3 改动文件 + 评审后可能微调）
| 文件 | 改动 |
|------|------|
| `LevelIt/.../Services/IntakeOffsetService.swift`（**新增**）| 计算可用余额 + 建任务 + 立即抵扣结算的纯逻辑（依赖 HealthKitDataStore、TaskStateMachine） |
| `LevelIt/.../Today/MealIntakeEditView.swift` | 新增抵扣 Section + 预览 + 触发 |
| `LevelIt/.../Services/HealthKitDataStore.swift`（如需）| 暴露"今日活动能量合计"读取（可能已有 todayWorkoutSummaries 可复用） |

### 2.5 边界 & 测试用例
- 今日运动 0 → 建任务但 offset=0，落 `created`，入口文案"今日暂无可用运动，已创建待磨平任务"。
- 运动 > 摄入（如 118 vs 75）→ 直接 settled，余额减少 75，后续再抵扣别的摄入用剩余 43。
- 连续抵扣多条摄入：第二条只能用剩余余额（验证 `D` 累加正确、不超发）。
- 该摄入已有 active 任务 → 不显示入口（防重复）。
- 抵扣后删除该摄入 → 关联任务一并处理（沿用现有 delete 逻辑）。
- 账本一致性单测：给定 E、已有任务 burned 列表、intake.kcal，验证 offset 与结清状态。

### 2.6 开放问题（评审拍板）
- **OP-1**：跨日抵扣旧摄入，余额按"今天"还是"摄入当天"？（拟定今天）
- **OP-2**：`E` 是否含本 App（Watch）写入 HealthKit 的运动？需真机核实写入与读取口径一致，否则改用"账本制"（只认 DebtTask.burnedCalories 总量，不读 HealthKit E）。
- **OP-3**：抵扣用的 `DebtTask` 默认运动模式（walk/mix/run）取什么？拟定跟随用户上次或默认 mix。

---

## 任务拆分与推进顺序

| 阶段 | 范围 | 文件数 | 依赖 |
|------|------|--------|------|
| **任务 A** | 需求一：餐次边缘提示 | 4（Shared×3 + AnalysisView×1）| 无，风险低，先做 |
| **任务 B** | 需求二：摄入抵扣磨平 | 3（新 Service + EditView + 可能 Store）| 依赖账本口径评审（OP-1~3） |

建议先做任务 A（独立、风险低、可快速真机验证），B 在账本开放问题确认后再实现。

## 风险与回滚
- 任务 A：纯增量（边缘检测 + 一个弹窗），不改既有非边缘路径，回滚只需移除 `edgeSuggestion` 调用。
- 任务 B：抵扣账本是新逻辑，集中在 `IntakeOffsetService`，单点可控；若 OP-2 口径不对，切"账本制"即可，不影响 UI。

---

*本文档为实现前的设计基线；评审通过后按任务 A→B 顺序实现，每个任务遵循"测试先行 + 三关验证 + 真机确认"。*
