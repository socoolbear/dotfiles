#!/bin/bash
# Claude Code Notification Hook
# macOS 시스템 알림을 표시합니다

# stdin에서 JSON 입력 읽기
INPUT=$(cat)

# 알림 유형과 메시지 추출
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"')
MESSAGE=$(echo "$INPUT" | jq -r '.message // "Claude Code 알림"')

# 알림 유형에 따른 제목 설정
case "$NOTIFICATION_TYPE" in
  "permission_prompt")
    TITLE="🔐 Claude Code - 권한 요청"
    SOUND="Ping"
    ;;
  "idle_prompt")
    TITLE="⏳ Claude Code - 입력 대기"
    SOUND="Glass"
    ;;
  "auth_success")
    TITLE="✅ Claude Code - 인증 성공"
    SOUND="Hero"
    ;;
  "elicitation_dialog")
    TITLE="💬 Claude Code - 입력 필요"
    SOUND="Ping"
    ;;
  *)
    TITLE="🤖 Claude Code"
    SOUND="Submarine"
    ;;
esac

# macOS 알림 표시
osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" sound name \"$SOUND\""

exit 0
