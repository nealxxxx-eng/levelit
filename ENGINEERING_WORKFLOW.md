# LevelIt 代码变更标准流程

本文定义所有代码变更前、中、后的必要检查点。目标是让 LevelIt 在快速迭代的同时，始终保持 iPhone、Watch、HealthKit、SwiftData、AI/R2 链路可控。

## 0. 适用范围

任何影响源码、Xcode 工程、共享模型、同步协议、隐私声明、构建配置、测试或发布材料的变更，都必须遵守本流程。纯文案或截图素材变更可以跳过完整构建，但仍要做对应的 diff 检查。

## 1. 变更前检查

### 1.1 判断变更类型

开始前先标记本次变更属于哪些类别：

- `Shared Logic`：`LevelItShared` 模型、状态机、热量计算、餐次判断、序列化。
- `iPhone App`：iPhone SwiftUI、SwiftData、相机、AI、HealthKit 导入、本地存储。
- `Watch App`：Watch 收件箱、运动、HealthKit、Haptic、Complication。
- `Sync`：`WCSyncService`、`WatchSyncReceiver`、消息类型、merge/去重/删除。
- `Privacy/Backend Boundary`：AI 上传、R2 保存、隐私政策、App Store 隐私声明。
- `Project/Build`：Xcode target、scheme、entitlements、assets、Info.plist。
- `Docs/Release`：README/架构/CHANGELOG/App Store 文案。

### 1.2 明确风险等级

- `P0`：会影响启动、构建、登录/授权、任务创建、运动记录、双端同步、数据丢失、隐私披露。
- `P1`：会影响核心路径体验，但有明确降级或绕过方式。
- `P2`：局部 UI、文案、统计展示、非核心优化。

P0/P1 变更必须先写清测试计划，再动手改代码。

### 1.3 文件边界

变更前先列出预计会改的文件，保持小 diff。默认不做跨模块大重构；如果必须重构，拆成“先加测试/保护网，再迁移，再删除旧路径”的多步变更。

## 2. 开发中规则

### 2.1 小 PR / 小提交

每个变更应该只解决一个明确问题。建议边界：

- 普通修复：1-5 个文件。
- 功能切片：不超过一个用户路径。
- 大文件如 `HomeView`、`AnalysisView`、`WCSyncService`、`WatchSyncReceiver`，每次只改一个逻辑点。

如果 diff 已经难以一屏解释清楚，先停下来拆分。

### 2.2 测试优先级

优先补共享层测试，而不是直接堆 UI 测试。需要补测试的情况：

- 状态流转、过期、结清、删除、撤销。
- 热量 clamp、估算分钟、运动导入抵扣。
- WatchConnectivity 字典序列化、timestamp 去重、merge 冲突。
- SwiftData 迁移、账本去重、每日余额。
- 隐私/后端边界的输入校验和降级路径。

当前目标：测试有效代码量 / 产品有效代码量逐步提升到 25%-35%。不要求一次达到，但每个核心逻辑变更都要让比例变好。

### 2.3 同步协议变更

任何 Sync 变更都要检查：

- 消息类型是否在 `AppConstants.WCMessageType` 中定义。
- `DebtTask.toDict/fromDict` 是否保留向后兼容。
- iPhone 和 Watch 是否都处理相同字段。
- 旧 timestamp 是否会被正确丢弃。
- 删除是否先通知 UI 退出，再删除 SwiftData 对象。
- 全量同步是否能修复漏消息，不会覆盖进行中任务进度。

### 2.4 隐私和后端边界变更

任何 AI/R2/HealthKit/照片相关变更都要检查：

- 隐私政策是否同步更新。
- App Store 隐私声明是否仍准确。
- Info.plist 权限文案是否与实际行为一致。
- HealthKit 数据是否仍只在本地使用。
- 照片上传、保存、保留周期、删除机制是否有明确说明。

## 3. 提交前三关

本地 `pre-commit` hook 会在 `git commit` 时自动运行轻量检查：

```bash
scripts/verify-three-gates.sh --skip-build
```

如果新机器还没有安装 hook，先运行：

```bash
scripts/install-git-hooks.sh
```

提交前运行：

```bash
scripts/verify-three-gates.sh
```

三关含义：

1. `swift test`：保护共享业务逻辑。
2. `xcodebuild -list`：保护 Xcode 工程结构。
3. `xcodebuild build`：保护 iPhone App + embedded Watch App 完整构建。

开发中可以快速预检：

```bash
scripts/verify-three-gates.sh --skip-build
```

但提交前不能跳过完整构建。hook 自动跑的是轻量版，完整构建仍需要在 push、PR 或发布前手动执行。

紧急情况下可以临时跳过 hook：

```bash
LEVELIT_SKIP_PRECOMMIT=1 git commit ...
```

只能用于保存 WIP 或处理非代码紧急提交，不能作为合入前验证。

## 4. 手测检查点

自动化通过后，根据变更类型选择手测。

### 4.1 Sync 手测

- iPhone 创建任务，Watch 收到相同食物、热量、运动模式、目标消耗。
- iPhone 编辑未开始任务/摄入，Watch 开始前能看到最新目标。
- Watch 开始、暂停、恢复、完成，iPhone 能看到进度和结清状态。
- iPhone 删除活跃任务/摄入，Watch 页面先退出再删除，不闪退。
- App 重启后全量同步能修复漏消息和孤儿任务。

### 4.2 HealthKit 手测

- Watch 授权后能启动真实 Workout。
- 心率和 activeEnergyBurned 能更新。
- 暂停/恢复后 duration 和 burnedCalories 不重置。
- iPhone 外部运动导入只抵扣一次，重启后不重复。
- HealthKit 拒绝授权时降级路径可用。

### 4.3 AI/R2/照片手测

- 拍照后能返回食物、emoji、热量和置信度。
- 低置信度/非食物/超时能进入合理降级。
- 本地图片能在美食墙和详情页加载。
- 删除摄入/任务后本地图片被清理。
- 隐私政策和 App Store 文案仍覆盖上传、R2、用途、保留周期、删除机制。

## 5. Review 检查点

Review 时先看风险，不先看风格：

- 是否有数据丢失或双端状态不一致风险。
- 是否绕过 `TaskStateMachine.transition()`。
- 是否在 `modelContext.save()` 前发送了不可回滚的同步消息。
- 是否把 HealthKit 或照片等敏感数据引入新上传路径。
- 是否新增了未声明的网络调用、日志或持久化。
- 是否有 SwiftData `@Model` 删除后 UI 继续引用的风险。
- 是否有大文件继续膨胀，需要拆出 service/helper。

## 6. 分支与集成策略

采用 trunk-based 思路：

- 短分支，频繁合入，main 始终可构建。
- 大功能用小切片逐步合入，不长期积压巨型分支。
- 每次合入前必须过三关。
- P0/P1 变更优先合测试和保护网，再合功能。
- 不把 `.build`、`.DS_Store`、`xcuserdata`、密钥、个人配置带进提交。

## 7. 发布前检查

发布或 TestFlight 前额外检查：

- `scripts/verify-three-gates.sh` 通过。
- `CHANGELOG.md` 更新用户可理解的变更。
- `ARCHITECTURE.md` 更新架构或数据流变化。
- `PRIVACY.md`、`AppStore资料.md` 与实际上传/存储行为一致。
- App Store 截图、权限文案、隐私标签一致。
- 真机完成至少一轮 iPhone + Watch 核心路径。

## 8. 度量方式

### 8.1 DORA

每周或每个版本记录：

- 部署/发布频率。
- 从开始改动到可发布的时间。
- 变更失败率。
- 故障恢复时间。

这些指标用于发现流程瓶颈，不用于考核代码行数。

### 8.2 SPACE

每轮迭代复盘时看：

- Satisfaction：开发体验是否顺手。
- Performance：核心用户路径是否更可靠。
- Activity：改动是否小而连续。
- Communication：文档和 review 是否让上下文清楚。
- Efficiency and Flow：是否被构建、签名、同步调试反复打断。

## 9. 最小完成定义

一个代码变更完成，必须同时满足：

- 代码实现完成。
- 必要测试已补或说明为什么不需要。
- 三关通过。
- 对应手测完成或明确标记未测风险。
- 文档/隐私/发布材料按影响范围更新。
- diff 中没有构建产物、系统文件、密钥或个人配置。
