#!/bin/bash
# Claude Code Notification Hook
# macOS 시스템 알림 + ntfy.sh 푸시 알림

# ntfy 설정
NTFY_TOPIC="${NTFY_TOPIC:-https://ntfy.sh/xxx}"
NTFY_TOKEN="${NTFY_TOKEN:-}"

# stdin에서 JSON 입력 읽기
INPUT=$(cat)

# 알림 유형과 메시지 추출
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"')
MESSAGE=$(echo "$INPUT" | jq -r '.message // "Claude Code 알림"')

# 알림 유형에 따른 제목 및 우선순위 설정
case "$NOTIFICATION_TYPE" in
  "permission_prompt")
    TITLE="🔐 권한 요청"
    SOUND="Ping"
    PRIORITY="high"
    TAGS="lock,claude"
    ;;
#  "idle_prompt")
#    TITLE="⏳ 입력 대기"
#    SOUND="Glass"
#    PRIORITY="default"
#    TAGS="hourglass,claude"
#    ;;
  "auth_success")
    TITLE="✅ 인증 성공"
    SOUND="Hero"
    PRIORITY="low"
    TAGS="white_check_mark,claude"
    ;;
  "elicitation_dialog")
    TITLE="💬 입력 필요"
    SOUND="Ping"
    PRIORITY="high"
    TAGS="speech_balloon,claude"
    ;;
  *)
    TITLE="🤖 Claude Code"
    SOUND="Submarine"
    PRIORITY="default"
    TAGS="robot,claude"
    ;;
esac

# macOS 알림 표시
osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" sound name \"$SOUND\"" 2>/dev/null &

# ntfy.sh 푸시 알림 전송
curl -s \
  -H "Authorization: Bearer $NTFY_TOKEN" \
  -H "Title: $TITLE" \
  -H "Priority: $PRIORITY" \
  -H "Tags: $TAGS" \
  -d "$MESSAGE" \
  "$NTFY_TOPIC" >/dev/null 2>&1 &

exit 0
