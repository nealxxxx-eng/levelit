# LevelIt / 磨平

LevelIt is an iPhone + Apple Watch health app that turns food intake into a clear, playable workout task.

核心闭环：

```text
iPhone 拍照或手动记录食物
  -> AI 估算热量
  -> 结合三餐/加餐规则生成磨平任务
  -> 同步到 Apple Watch 执行运动
  -> 完成后回传进度、结清状态，并支持分享
```

当前仓库包含 iPhone App、Watch App、共享 Swift Package、阿里云 Node 后端和工程协作脚本。

## Repository Layout

```text
LevelIt/
  LevelIt.xcodeproj
  LevelIt/                         iPhone App
  LevelItWatch Watch App/          Apple Watch App
  LevelItTests/                    iOS test target

LevelItShared/                     Swift Package shared by iPhone and Watch
  Sources/Models/                  DebtTask, UserProfile, PKChallenge, MealIntake, etc.
  Sources/StateMachine/            TaskStateMachine, CalorieCalculator, meal logic
  Tests/                           shared logic regression tests

aliyun-backend/                    ECS-ready Node backend
  server.js                        auth + profile routes
  api/pk.js                        PK challenge routes
  api/apns.js                      APNs push helper

scripts/                           local quality gates and git hook installer
docs/*.md                          architecture, privacy, workflow, App Store notes
```

## Requirements

- macOS with Xcode 17 or later
- iOS 17+ target
- watchOS 10+ target
- Swift Package Manager
- Node.js 20+ for `aliyun-backend`
- GitHub CLI (`gh`) if you plan to publish branches or PRs

## First-Time Setup

Clone the repository:

```bash
git clone https://github.com/nealxxxx-eng/levelit.git
cd levelit
```

Install the local pre-commit hook:

```bash
scripts/install-git-hooks.sh
```

Open the app project:

```bash
open LevelIt/LevelIt.xcodeproj
```

Use the `LevelIt` scheme. The app embeds the Watch app, so the iPhone build also validates the Watch target.

## Quality Gates

Before committing meaningful code changes, run the full three-gate check:

```bash
scripts/verify-three-gates.sh
```

The three gates are:

1. `swift test` for `LevelItShared`
2. `xcodebuild -list` for project structure
3. full iPhone + embedded Watch build

During active development, use the faster check:

```bash
scripts/verify-three-gates.sh --skip-build
```

Do not use the skipped-build mode as the final validation before merging or releasing.

## Backend

The iOS app currently talks to the Aliyun backend at `http://39.105.196.84/api`.

Main backend endpoints:

```text
POST /api/analyze
POST /api/estimate-daily-energy
POST /api/auth/register
POST /api/auth/login
GET  /api/auth/me
PUT  /api/auth/profile
POST /api/pk/challenges
GET  /api/pk/challenges
POST /api/pk/claim
PUT  /api/pk/challenges/:id/progress
```

Run the backend locally:

```bash
cd aliyun-backend
export LEVELIT_AUTH_SECRET="replace-with-a-long-random-secret"
export LEVELIT_DB_FILE="./users.json"
export LEVELIT_PK_DB_FILE="./pk.json"
export PORT=3000
npm start
```

For production, keep secrets in environment variables or server-side config files. Never commit real API keys, APNs keys, R2 credentials, `.env` files, provisioning profiles, or private keys.

## Important Privacy Boundary

Food photos are uploaded for AI analysis and may be stored in Cloudflare R2 for future analysis and quality improvement. This behavior must stay aligned across:

- `PRIVACY.md`
- `AppStore资料.md`
- Info.plist permission strings
- backend storage/deletion behavior

HealthKit data should remain local unless a future product decision explicitly changes that boundary and the privacy documents are updated first.

## Development Rules

- Keep diffs small and reviewable.
- Prefer shared-layer tests for business logic changes.
- Route all task status changes through `TaskStateMachine.transition()`.
- Treat iPhone-Watch sync changes as high risk.
- Do not commit `.build`, `DerivedData`, `xcuserdata`, `.DS_Store`, logs, secrets, or local environment files.
- For sync-sensitive changes, manually test task create/edit/delete, Watch start/pause/resume/complete, and HealthKit import dedupe.

More detail:

- `ENGINEERING_WORKFLOW.md`
- `QUALITY_GATES.md`
- `ARCHITECTURE.md`
- `PRIVACY.md`

## Common Commands

```bash
# Shared package tests only
cd LevelItShared
swift test

# Full app build from repository root
xcodebuild \
  -project LevelIt/LevelIt.xcodeproj \
  -scheme LevelIt \
  -destination 'generic/platform=iOS Simulator' \
  build

# Full project gates
scripts/verify-three-gates.sh
```

## Team Workflow

Recommended branch flow:

```bash
git checkout main
git pull
git checkout -b feature/short-description
scripts/verify-three-gates.sh --skip-build
```

Before merge:

```bash
scripts/verify-three-gates.sh
git status --short
```

Then open a pull request and include:

- what changed
- why it changed
- validation commands
- manual iPhone/Watch checks if sync, HealthKit, AI upload, or PK behavior changed

