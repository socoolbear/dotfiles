# Agent Orchestration Rules

## Delegation First

이 저장소에서는 **단순 작업도 에이전트에게 위임**하는 것을 권장합니다.

## Task Routing

| 작업 유형 | 권장 에이전트 | 모델 |
|-----------|--------------|------|
| Makefile 수정 | `executor` | sonnet |
| Shell 스크립트 작성 | `executor` | sonnet |
| 설정 파일 추가 | `executor-low` | haiku |
| 문서 작성 | `writer` | haiku |
| 구조 분석 | `explore` | haiku |

## Response Language

- 모든 응답은 **한국어**로 작성
- Git 커밋 메시지도 **한국어**로 작성
- 영어와 한국어 혼용 시 **띄어쓰기 추가** (예: "Makefile 에서")

## Target Environment

- **macOS** 사용자 대상
- Homebrew, XDG Base Directory 사용 가정
- Shell: zsh (oh-my-zsh)

## Verification

작업 완료 전 반드시 확인:

1. `make sync` 정상 동작
2. 기존 심볼릭 링크 영향 없음
3. 새 파일/디렉토리 올바른 위치에 생성
