#!/bin/bash
# Claude Code Stop Hook - 작업 완료 알림
# macOS 시스템 알림 + ntfy.sh 푸시 알림

# ntfy 설정
NTFY_TOPIC="${NTFY_TOPIC:-https://ntfy.sh/claude-code-RgoJjv6AcNnZlCGU}"
NTFY_TOKEN="${NTFY_TOKEN:-}"

# stdin에서 JSON 입력 읽기
INPUT=$(cat)

# 디버그 로그
echo "$(date '+%Y-%m-%d %H:%M:%S') | STOP | $INPUT" >> "$HOME/.claude/scripts/notify.log"

# 알림 설정
TITLE="✅ 작업 완료"
MESSAGE="Claude Code 작업이 완료되었습니다"
SOUND="Glass"
PRIORITY="high"
TAGS="white_check_mark,claude"

# macOS 알림 표시 (terminal-notifier 사용)
if command -v terminal-notifier &>/dev/null; then
  terminal-notifier \
    -title "$TITLE" \
    -message "$MESSAGE" \
    -sound "$SOUND" \
    -group "claude-code" \
    -activate "com.mitchellh.ghostty" \
    &>/dev/null &
fi

# ntfy.sh 푸시 알림 전송
curl -s \
  -H "Authorization: Bearer $NTFY_TOKEN" \
  -H "Title: $TITLE" \
  -H "Priority: $PRIORITY" \
  -H "Tags: $TAGS" \
  -d "$MESSAGE" \
  "$NTFY_TOPIC" >/dev/null 2>&1 &

exit 0
