# 자기개선 루프 & 피드백 라우팅

> `~/.claude/AGENTS.md` 의 자기개선 항목 상세. **사용자에게 수정·피드백을 받을 때마다** 이 문서의 라우팅 표를 참조하여 적절한 위치에 영구화할 것.

## 자기개선 루프

- 사용자에게 수정을 받을 때마다: 해당 패턴을 **프로젝트 내 파일** 에 기록 (AGENTS.md / docs/ / .claude/skills/ / .claude/rules/)
- 같은 실수를 반복하지 않도록 스스로 규칙을 작성
- 실수율이 낮아질 때까지 이 교훈들을 반복해서 다듬을 것
- 세션 시작 시 해당 프로젝트의 교훈 목록을 먼저 검토

## 피드백은 auto-memory 가 아니라 repo 에 기록 (중요)

- Claude Code 의 auto-memory 는 **세션/환경이 달라지면 유지되지 않는다**. 다른 AI Agent (Codex, Cursor 등) 나 새 기기에서 동일한 규칙을 적용받으려면 **프로젝트 repo 안 파일** 에 저장해야 한다.
- auto-memory 저장은 세션 내 빠른 참조용으로만 사용. **장기 신뢰 소스는 repo 안 파일**

### 피드백 유형별 반영 위치

| 피드백 유형 | 반영 위치 |
|---|---|
| 워크플로우 / 작성 규칙 | 프로젝트 `AGENTS.md` 또는 `docs/` |
| 도메인 사실관계 (수치, 경력, 고유명사) | `docs/{domain}.md` |
| 특정 작업 자동화 규칙 | `.claude/skills/{skill}/SKILL.md` |
| 자동 실행 Hook / 권한 | `.claude/settings.json` (update-config 스킬 활용) |
| 코딩 스타일 규칙 | `.claude/rules/` 또는 `docs/coding-style.md` |

### 반영 워크플로우

1. 피드백 수신 → 유형에 맞는 위치 선택
2. 해당 파일에 유사 규칙 있는지 Grep 확인
3. 기존 섹션 확장 or 누적 섹션에 추가
4. auto-memory 에는 빠른 참조용 짧은 요약만 (선택)
