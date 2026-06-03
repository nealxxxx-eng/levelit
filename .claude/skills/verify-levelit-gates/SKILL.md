---
name: verify-levelit-gates
description: 运行 LevelIt 提交前的三关预检（共享测试 + Xcode 工程解析 + iPhone+Watch 完整构建），解析输出并报告通过/失败门禁。改完 Swift 代码后由用户或 Claude 触发。
---

# LevelIt 三关预检

封装 `scripts/verify-three-gates.sh`，让"提交前必须过三关"成为对话级习惯。

## 何时调用

- 用户输入 `/verify-levelit-gates`
- Claude 在以下场景**主动建议**调用（不要直接跑）：
  - 改动了 `LevelItShared/Sources/` 或 `LevelIt/LevelIt/` 或 `LevelIt/LevelItWatch Watch App/` 下的 .swift 文件
  - 改动了 `LevelIt.xcodeproj/project.pbxproj`
  - 准备 commit / 创建 PR 前

## 参数

- `--skip-build`（可选）：跳过完整构建，仅做共享测试 + 工程解析（开发中预检）。**不能在准备提交时跳过。**

## 执行

```bash
cd ~/CC/levelit
scripts/verify-three-gates.sh $ARGUMENTS
```

捕获 stdout + stderr + exit code。

## 输出解析

把脚本输出按三关拆开汇报：

```
## LevelIt 三关预检结果

| 门禁 | 状态 | 用时 | 备注 |
|------|------|------|------|
| 1. 共享测试 (LevelItShared) | ✅/❌ | Xs | 失败时摘关键报错 |
| 2. Xcode 工程解析 | ✅/❌ | Xs | ... |
| 3. iPhone + Watch 构建 | ✅/❌ | Xs | ... |

总耗时: Xs
退出码: N
```

如果失败：
- 引用具体报错行号
- 给修复建议（不要直接动手改）
- 提醒用户：`CLAUDE.md` 要求三关全过才能 commit

如果全过：
- 提示可以走 `/commit` 或正常 git 流程
- 提醒同步敏感改动还需手测 iPhone↔Watch（创建/编辑/删除任务、运动开始/暂停/完成、HealthKit 导入去重）

## 不要做的事

- 不要修改任何源码（仅运行 + 报告）
- 不要建议用 `--no-verify` 跳过 git hook
- 不要在三关失败时执意 commit
