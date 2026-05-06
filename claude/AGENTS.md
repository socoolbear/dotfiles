# Claude Code Global Settings

## 언어
- 한국어로 응답
- **존댓말로 응답** (해요체/합니다체). 반말/평어체 금지
- Git 커밋 메시지도 한국어로 작성 (커밋 메시지 본문은 간결한 평어체 OK — 설명문 형식이므로)
- 영어와 한국어 혼용 시 **띄어쓰기 추가** (예: "Makefile 에서")

## 환경
- macOS 사용자 대상
- Homebrew, XDG Base Directory 사용 가정
- Shell: zsh (oh-my-zsh)

## 워크플로우 (요약)

| # | 룰 (한 줄) | 트리거 시 참조 |
|---|---|---|
| 1 | 사소하지 않은 작업은 계획 모드로 시작 | `@docs/workflow.md` |
| 2 | 조사·탐색·병렬 분석은 서브에이전트로 분리 | `@docs/workflow.md` |
| 3 | 사용자 피드백은 auto-memory 가 아닌 **repo 파일** 에 기록 | `@docs/feedback-loop.md` |
| 4 | 작동을 증명하기 전 완료 표시 금지 | `@docs/workflow.md` |
| 5 | 사소하지 않은 변경은 "더 우아한 방법?" 자문 후 진행 | `@docs/workflow.md` |
| 6 | 버그 리포트는 자율적으로 끝까지 수정 | `@docs/workflow.md` |

> 위 표의 "트리거 시 참조" 컬럼은 해당 상황에 진입했을 때 **반드시 해당 docs 를 먼저 읽어야 함** 을 의미합니다. 한 줄 룰만으로 판단하지 말 것.

## 핵심 원칙

- **단순함 우선**: 모든 변경은 최대한 단순하게. 건드리는 코드는 최소화.
- **게으름 금지**: 근본 원인을 찾을 것. 임시방편 없음. 시니어 개발자 기준으로.
- **최소 영향**: 꼭 필요한 부분만 수정. 새로운 버그를 만들지 말 것.

## 상세 가이드

- 워크플로우 6단계 + 작업 관리: `@docs/workflow.md`
- 자기개선 루프 + 피드백 라우팅: `@docs/feedback-loop.md`
- 코딩 스타일: `@rules/coding-style.md`
- CLI 도구 사용 규칙: `@rules/cli-tools.md`
