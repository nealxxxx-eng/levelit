#!/usr/bin/env bash
# PostToolUse hook: 编辑 .swift 文件后自动 swift-format
# 未安装 swift-format 时静默跳过，不阻塞工作流。

set -u

payload="$(cat)"
file_path="$(printf '%s' "$payload" | /usr/bin/jq -r '.tool_input.file_path // empty' 2>/dev/null)"

[[ -z "$file_path" ]] && exit 0
[[ "$file_path" != *.swift ]] && exit 0
[[ ! -f "$file_path" ]] && exit 0

if command -v swift-format >/dev/null 2>&1; then
  swift-format --in-place "$file_path" 2>/dev/null || true
fi

exit 0
