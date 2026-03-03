#!/bin/bash
set -euo pipefail

# 작업 완료 후 자동 검토 훅
# Stop 이벤트 시 한 번만 검토 프롬프트를 출력하고,
# 두 번째 Stop 에서는 조용히 종료하여 무한 루프 방지

REVIEW_DIR="/tmp/claude-code-review"
mkdir -p "${REVIEW_DIR}"

# 1일 이상 된 세션 파일 정리
find "${REVIEW_DIR}" -type f -mtime +1 -delete 2>/dev/null || true

# PPID (Claude Code 프로세스) 를 세션 식별자로 사용
SESSION_FILE="${REVIEW_DIR}/${PPID}"

if [[ -f "${SESSION_FILE}" ]]; then
  # 이미 검토 완료 — 조용히 종료
  rm -f "${SESSION_FILE}"
  exit 0
fi

# 검토 트리거 표시
touch "${SESSION_FILE}"

# Claude 에게 검토 프롬프트 전달
cat <<'EOF'
[자동 검토] 작업을 마무리하기 전에 다음을 점검해주세요:
- 변경한 코드에서 발생 가능한 오류나 엣지 케이스 예측
- 개선이 필요한 부분이 있다면 즉시 수정
- 문제가 없다면 그대로 종료
EOF
