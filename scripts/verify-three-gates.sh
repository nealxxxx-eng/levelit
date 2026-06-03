#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/levelit-three-gates-build}"
DESTINATION="${DESTINATION:-generic/platform=iOS}"

usage() {
  cat <<'EOF'
Usage: scripts/verify-three-gates.sh [--skip-build]

Runs LevelIt's required local quality gates:
  1. Shared package tests: swift test
  2. Xcode project sanity: xcodebuild -list
  3. Full iOS + embedded Watch build: xcodebuild build

Environment overrides:
  DESTINATION       Xcode destination. Default: generic/platform=iOS
  DERIVED_DATA_PATH DerivedData output path. Default: /tmp/levelit-three-gates-build

Options:
  --skip-build      Run gates 1-2 only. Use only for quick preflight, not before commit.
  -h, --help        Show this help.
EOF
}

SKIP_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --skip-build)
      SKIP_BUILD=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run_step() {
  local title="$1"
  shift
  printf '\n==> %s\n' "$title"
  "$@"
}

run_step "Gate 1/3: LevelItShared unit tests" \
  bash -lc "cd '$ROOT_DIR/LevelItShared' && swift test"

run_step "Gate 2/3: Xcode project sanity" \
  xcodebuild -project "$ROOT_DIR/LevelIt/LevelIt.xcodeproj" -list

if [[ "$SKIP_BUILD" == "1" ]]; then
  cat <<'EOF'

==> Gate 3/3: skipped by --skip-build
This is acceptable for a quick preflight only. Do not treat this as a pre-commit pass.
EOF
else
  run_step "Gate 3/3: full iOS app build with embedded Watch app" \
    xcodebuild \
      -project "$ROOT_DIR/LevelIt/LevelIt.xcodeproj" \
      -scheme LevelIt \
      -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      build
fi

cat <<'EOF'

Automated gates completed.

Manual regression checklist still required for sync-sensitive changes:
  - iPhone creates a task; Watch receives the same food, calories, mode, and target.
  - Editing an unstarted intake/task on iPhone updates Watch before workout starts.
  - Watch starts, pauses/resumes, completes, and iPhone receives progress + settled state.
  - Deleting active tasks/intakes on iPhone pops related Watch UI and removes stale tasks.
  - HealthKit import deducts once only and does not duplicate after relaunch.
EOF
