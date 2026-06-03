# LevelIt 三关验证

每次改动在提交前必须过三关。目标不是形式主义，而是保护最容易回归的三条边界：共享业务逻辑、Xcode 工程可构建、iPhone/Watch 同步行为。

完整工程变更流程见 `ENGINEERING_WORKFLOW.md`。本文只定义提交前三关。

## 一条命令

```bash
scripts/verify-three-gates.sh
```

脚本会执行：

1. `cd LevelItShared && swift test`
2. `xcodebuild -project LevelIt/LevelIt.xcodeproj -list`
3. `xcodebuild -project LevelIt/LevelIt.xcodeproj -scheme LevelIt -destination generic/platform=iOS build`

可以用 `--skip-build` 做快速预检，但提交前不能跳过第三关。

```bash
scripts/verify-three-gates.sh --skip-build
```

本地 commit 会通过 Git hook 自动运行轻量预检。首次配置或换机器后运行：

```bash
scripts/install-git-hooks.sh
```

## 三关定义

### Gate 1: 共享层测试

覆盖 `LevelItShared` 中的模型、状态机、热量计算、餐次判定、WatchConnectivity 序列化等逻辑。任何触碰共享模型、状态流转、热量计算、导入抵扣的改动，都必须补或更新测试。

### Gate 2: Xcode 工程解析

`xcodebuild -list` 用来快速确认工程文件、target、scheme 和本地包依赖没有损坏。它速度快，能提前发现项目文件冲突、target 丢失、scheme 不可见这类问题。

### Gate 3: 完整构建

`LevelIt` scheme 会构建 iPhone App，并包含 Watch App 依赖。该关能捕获 SwiftUI、SwiftData、Watch target、签名和资源引用层面的编译问题。

## 同步敏感改动的手测清单

自动化验证通过后，以下场景仍需要真机或模拟器手测：

- iPhone 创建任务后，Watch 收到相同的食物、热量、运动模式和目标消耗。
- iPhone 编辑未开始的摄入/任务后，Watch 开始运动前能看到更新后的目标。
- Watch 开始、暂停、恢复、完成运动后，iPhone 能收到进度和结清状态。
- iPhone 删除活跃任务/摄入后，Watch 相关页面能先退出，再删除本地任务，不能闪退。
- HealthKit 外部运动导入只抵扣一次，重启 App 后不会重复导入。

## 失败处理

- Gate 1 失败：优先修测试暴露的业务逻辑，不要直接改测试预期。
- Gate 2 失败：检查 `LevelIt.xcodeproj/project.pbxproj` 和 package 引用。
- Gate 3 失败：先看第一个 Swift 编译错误，避免被后续级联错误带偏。
- 手测失败：记录复现路径、两端当前任务状态、最后一次 WC 消息类型，再修复。
