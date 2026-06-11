# CLI Tool Preferences

> 모든 셸 작업에서 아래 도구를 우선 사용. 이 dotfiles 의 `Brewfile` 에 모두 등재되어 있으므로 `make brew` 로 일괄 설치 가능.
>
> **우선순위**: Claude Code 내장 도구 (Read / Grep / Glob) 가 커버하는 작업은 내장 도구가 우선 (내장 Grep 은 ripgrep 기반이라 rg 의 속도·기능을 이미 활용 중). 아래 규칙은 **Bash 를 직접 쓸 때** 적용됩니다.

## 표준 도구 대체 (항시)

- 파일 탐색: `find` 대신 `fd`
- 텍스트 검색: `grep` 대신 `rg` (ripgrep)
- 파일 내용 출력: `cat` 대신 `bat` (에이전트는 Read 도구)
- 디렉토리 목록: `ls` 대신 `eza`

> 위 4 개 대체는 PreToolUse hook (`claude/scripts/enforce-cli-tools.sh`, `settings.json` 에 등록) 이 자동 차단으로 강제합니다. 대체 도구가 미설치된 머신에선 차단하지 않습니다 (표준 도구 폴백 허용).

## 코드 / 데이터 처리

- 코드 구조 검색·리팩터링: `ast-grep` 적극 활용
- JSON / YAML 파싱: `jq` 와 `yq` 를 파이프라인으로 연결

## 외부 서비스 / 자동화

- Python 린팅·포매팅: `ruff`
- GitHub 작업 (PR / 이슈 등): `gh` CLI **비대화형 모드** (`--json` 출력 강제)
- **모든** 외부 서비스 CLI: 비대화형 (`--yes` / `--quiet`) + 머신 파싱 가능 포맷 (`--format json`) 강제

## 설치

이 dotfiles 의 Brewfile 에 모두 포함되어 있습니다:

```bash
make brew    # Brewfile 일괄 적용
```

미설치 환경에선 표준 도구 (`find` / `grep` / `cat` / `ls`) 로 폴백하되, 가능하면 위 명령으로 설치 권장.

## 머신별 권한 (참고)

Bash 권한 프롬프트를 줄이려면 `~/.claude/settings.local.json` 의 `permissions.allow` 에
`Bash(fd:*)`, `Bash(rg:*)`, `Bash(bat:*)`, `Bash(eza:*)` 등을 추가할 수 있습니다.

이 파일은 `.gitignore` 되어 머신별로 관리됩니다 (Harness CONTRACTS § 3-7 의 "머신별 레이어" 패턴).
현재 글로벌 `claude/settings.json` 은 `defaultMode: "auto"` 이므로 보통 불필요합니다.
