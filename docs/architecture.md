# 아키텍처

## Makefile 기반 관리

- **단일 파일**: `[ -L ... ] || ln -sf` 패턴으로 멱등 심볼릭 링크
- **디렉토리**: `rm -rf` 후 `ln -sf` 패턴으로 전체 교체
- **프레임워크**: oh-my-zsh, oh-my-tmux 자동 설치

## Homebrew 예약 갱신 (launchd)

Homebrew 갱신을 **정해진 시각에만** 수행합니다. 작업 중인 `brew` 명령이 자동 갱신에 붙잡히거나, 로그인할 때마다 갱신이 시작되는 일을 없애기 위한 구성입니다.

- `zsh/zshrc` 의 `HOMEBREW_NO_AUTO_UPDATE=1` — brew 명령이 스스로 갱신하지 않음 (기존 `HOMEBREW_AUTO_UPDATE_SECS` 대체)
- `launchd/com.socoolbear.brew-scheduled-update.plist` — **예약 시각 매일 04:30** (`StartCalendarInterval`), `RunAtLoad` 는 꺼둠
- `scripts/brew-scheduled-update.sh` — `brew update` → `brew upgrade --formula` → `brew upgrade --cask` → `brew cleanup --prune=30`. 한 단계가 실패해도 다음 단계는 돌고, 두 upgrade 는 실패하면 60초 뒤 한 번 더 시도합니다

### 사람 없는 새벽 실행에 맞춘 처리

| 문제 | 처리 |
|------|------|
| launchd 가 맥이 잠깐 깬 상태 (darkwake) 에서 작업을 띄우고, 맥이 수십 초 안에 다시 잠들어 다운로드가 실패함 | 스크립트가 끝날 때까지 `caffeinate -i -w <pid>` 로 잠자기를 막음 |
| pkg 설치기를 쓰는 cask (`corretto@25` · `session-manager-plugin` 등) 는 sudo 비밀번호가 필요해 늘 실패함 | 예약 실행에서는 건너뛰고, 로그에 `손으로 올릴 것 (sudo 필요): brew upgrade --cask …` 를 남김 |
| 실패해도 로그에만 남아 모름 | 실패한 단계가 있거나 손으로 올릴 cask 가 있으면 macOS 알림을 띄움. 로그 끝에 `결과:` 줄이 있음 |

### 지연 실행 처리

launchd 는 예약 시각에 맥이 잠들어 있었으면 **깨어난 직후** 작업을 실행합니다. 이때 실제 실행 시각이 예약 시각과 크게 어긋날 수 있어, 스크립트가 실행 시각을 스스로 검사합니다.

| 실행 시점 | 동작 |
|------|------|
| 실행 허용 구간 (03:00~08:00) 안 | 실행 |
| 허용 구간 밖의 지연 실행 | 건너뛰고 다음 예약 대기 |
| 마지막 실행 후 7 일 초과 (`OVERDUE_DAYS`) | 허용 구간 무시하고 1 회 실행 — 갱신이 무한정 밀리는 것 방지 |
| 실행 기록이 아예 없을 때 (최초 등록 직후) | 기록만 초기화하고 다음 예약으로 넘김 — 등록하자마자 대규모 업그레이드 방지 |

허용 구간은 스크립트의 `RUN_WINDOW_START` / `RUN_WINDOW_END` 로 정합니다. **예약 시각(plist)을 바꾸면 이 구간도 함께 옮겨야** 정상 실행이 건너뛰어지지 않습니다.

### 운영

- 상태 파일: `~/.local/state/brew-scheduled-update/last-run` (마지막 실행 시각)
- 로그: `~/Library/Logs/brew-scheduled-update.log` (1MB 초과 시 `.1` 로 1 회 로테이션)
- 예약을 기다리지 않고 즉시 실행 / 로그 확인: `make brew-scheduled-update`, `make brew-scheduled-update-log`
- 예약 등록은 심링크만으로 되지 않으므로 `make sync` 가 `launchctl bootout` → `bootstrap` 으로 재등록합니다 (멱등). `make clean` 은 `bootout` 후 심링크를 제거합니다.
- 등록 상태 확인: `launchctl print gui/$(id -u)/com.socoolbear.brew-scheduled-update`
- 알림은 `terminal-notifier` (Brewfile) 로 띄워 누르면 로그가 열립니다. terminal-notifier 가 없거나 시스템 설정 > 알림 에서 허용되지 않았으면 (exit 3) `osascript` 로 띄우고, 이 알림은 누르면 스크립트 편집기가 열리므로 본문의 로그 명령을 씁니다

> 과거에 쓰던 `brew autoupdate` (homebrew/autoupdate 탭) 는 로그인 시 + 24시간 간격이라 실행 시각을 지정할 수 없어 제거했습니다. 새 장비에서 실수로 다시 깔았다면 `brew autoupdate delete` 로 지우세요.

## 주 1회 장비 점검 (launchd)

dotfiles-doctor 의 장비 상태 점검 (`.claude/skills/dotfiles-doctor/scripts/machine.sh` — MCP 평문 비밀값 · 폐기된 MCP 패키지 · 플러그인 정합 · 예약 작업 · 가드 기록 · 비밀값 사본 · cc-marketplace 요약) 을 주 1회 자동으로 돌립니다. 홈 폴더를 보는 점검이라 GitHub Actions 같은 원격에서는 못 합니다.

- `launchd/com.socoolbear.dotfiles-machine-check.plist` — **매주 월요일 14:00**. 새벽 예약은 darkwake 에서 떠 곧 다시 잠들고 네트워크가 없을 수 있어 사람이 쓰는 평일 낮으로 잡았습니다. 그 시각에 잠들어 있었으면 깨어난 직후 한 번 돌고, 언제 돌아도 되는 점검이라 시각을 거르지 않습니다
- `scripts/machine-check-scheduled.sh` (`~/.local/bin/dotfiles-machine-check`) — launchd 의 짧은 PATH 에 Homebrew · mise 경로를 더하고, 링크를 따라 저장소 위치를 찾아 `machine.sh` 를 부릅니다. 전체 출력은 로그에, **FAIL · WARN 이 1건 이상일 때만 메일 한 통**을 보냅니다 (macOS 알림은 띄우지 않음). 메일은 `claude -p` (모델 haiku, 도구는 Gmail 보내기 하나만 허용) 가 claude.ai 의 Gmail 커넥터로 `git config user.email` 에게 보내고, 받는 주소는 로그 · 저장소에 남기지 않습니다. 본문은 스크립트가 만든 고정 문구 — 건수 · 항목이 나온 영역 제목 (`machine.sh` 의 `## ` 줄) · `make machine-check-log` 안내뿐이고, 항목 줄은 서버 이름 · 경로가 섞일 수 있어 넣지 않습니다. 제목에 장비 이름 (`scutil --get LocalHostName`) 이 들어갑니다. 한 번 보내는 데 약 10초 · $0.01. 성공은 모델의 답이 아니라 보내기 도구가 돌려준 메시지 id 로 판정하고 로그에 `메일: 보냄 / 실패 (이유)` 를 남깁니다
- 발송에 실패하면 (claude 없음 · 로그인 · 커넥터 끊김 · 시간 초과 180초 · 받는 주소 없음) 다른 알림 없이 `~/.local/state/dotfiles-machine-check/mail-failed` 에 시각과 이유를 남기고 끝냅니다 (exit 0). 다음 `machine.sh` 가 이 파일을 WARN 으로 내고, 세션 시작 때의 doctor 제안 (`suggest.sh`) 도 이 파일을 봅니다. 다음 발송이 성공하면 지워집니다
- 없는 것은 실패로 치지 않습니다: 네트워크가 없으면 npm 폐기 표시 · cc-marketplace CI 결과는 INFO 로 건너뛰고, `gh` 인증이 없어도 INFO, cc-marketplace 체크아웃 · 가드 기록 · MCP 설정이 없으면 그 항목을 건너뜁니다. 반대로 점검에 쓰는 명령 (`jq` · `git` · `gh` · `npm` · `node`) 을 못 찾으면 WARN 입니다 — 조용히 0건이 되지 않게
- 로그: `~/Library/Logs/dotfiles-machine-check.log` (1MB 초과 시 `.1` 로 1 회 로테이션). 즉시 실행 / 로그 확인 / 메일 시험: `make machine-check`, `make machine-check-log`, `dotfiles-machine-check --test-mail` (제목에 "(시험)", 실패 표시 파일은 건드리지 않음)
- 등록 · 해제는 Homebrew 예약과 같이 `make sync` (`bootout` → `bootstrap`) · `make clean` (`bootout`). 끄려면 `launchctl bootout gui/$(id -u)/com.socoolbear.dotfiles-machine-check` (다음 `make sync` 때 다시 등록됩니다). 점검은 두고 메일만 받지 않으려면 Gmail 에서 제목 `dotfiles 장비 점검` 을 거르는 필터를 겁니다

## 자동 갱신 (launchd + 메뉴 막대)

dotfiles · cc-marketplace 체크아웃 · Claude 플러그인을 Claude 세션과 별개로 하루 1회 받습니다. **안전할 때만 조용히 받고, 못 받았을 때만 메뉴 막대에 뜹니다** — 평소에는 아무것도 보이지 않습니다.

- `launchd/com.socoolbear.dotfiles-auto-update.plist` — **매일 11:00**. 장비 점검과 같은 이유 (새벽 darkwake 는 곧 다시 잠들고 네트워크가 없을 수 있음) 로 사람이 쓰는 오전으로 잡았고, 받은 변경이 그날 세션부터 쓰입니다. 잠들어 있었으면 깨어난 직후 한 번 돕니다
- `scripts/dotfiles-auto-update.sh` (`~/.local/bin/dotfiles-auto-update`) 의 대상:
  1. **dotfiles** — `git fetch` 뒤 조건이 맞으면 `git merge --ff-only` 하고 `make sync`. `make sync` 가 실패하면 실패로 적고 다음 실행 때 다시 돌립니다. Brewfile 이 바뀌었으면 설치하지 않고 "make update 필요" 로만 적습니다 (다음 실행이 `brew bundle check` 로 다시 보고, 다 깔렸으면 지움)
  2. **cc-marketplace 체크아웃** — `~/.claude/workstyle` 이 체크아웃을 가리키는 심링크일 때만 (경로는 그 링크에서 찾음). 같은 조건으로 ff-only
  3. **Claude 플러그인** — 세션 시작 때의 자동 갱신과 같은 범위: `autoUpdate` 가 켜진 마켓플레이스 (값이 없으면 공식 마켓플레이스만) 를 `claude plugin marketplace update` 하고 그 마켓플레이스의 켜 둔 플러그인을 `claude plugin update` 합니다. 새 명령 승인을 요구하는 플러그인은 `-y` 로 넘기지 않고 손 필요로 둡니다. `claude plugin` 이 `settings.json` 키 순서를 바꾸면 내용이 같을 때 원래 글로 되돌립니다
- **받는 조건 (셋 다)**: 미커밋 · 미추적 변경이 없다 / 기본 브랜치에 있다 / 원격보다 앞선 커밋이 없다. 하나라도 어긋나면 fetch 만 하고 작업 트리는 건드리지 않습니다 (reset · stash · clean 을 쓰지 않음). 받기 전 커밋은 로그에 남기고 되돌리기는 사람이 합니다 (`git reset --keep <커밋>`)
- **스스로를 갱신합니다.** dotfiles 를 받으면 새 판을 `exec` 로 다시 불러 나머지 단계를 새 판이 하고, 끝줄은 `main "$@"; exit $?` 한 줄이라 바뀐 파일의 뒷부분을 읽지 않습니다
- **`make sync` 가 자기 작업을 죽이지 않게** — 실행 중인 launchd 작업을 `bootout` 하면 launchd 가 그 작업을 죽입니다. 그래서 자동 갱신이 부른 `make sync` (`DOTFILES_AUTO_UPDATE_RUNNING=1`) 는 이 작업을 다시 걸지 않고 등록이 없을 때만 겁니다. 예약 설정 (plist) 의 변경은 다음에 손으로 `make sync` 할 때 반영됩니다
- **1Password 승인 창이 뜨지 않게** — GitHub 의 SSH 원격 (`git@github.com:` · `ssh://git@github.com/`) 은 HTTPS 로 바꿔 받습니다 (`GIT_CONFIG_*` 환경 변수, 저장소 설정은 그대로). 받기만 하므로 공개 저장소는 인증이 필요 없습니다. 그래도 SSH 로 남는 원격 (다른 호스트 · ssh 설정의 별칭) 은 받지 않고 손 필요로 둡니다
- **상태 파일** `~/.local/state/dotfiles-update/status` — 대상마다 `최신 / 받음 / 손 필요 (이유) / 실패 (이유) / 받아오지 못함 / 건너뜀` 과 그 상태가 시작된 시각, 마지막 실행 시각. `make auto-update-log` 가 사람이 읽기 좋게 보여 줍니다. 없는 것 (체크아웃 · claude) 은 건너뜀, 없는 명령 (`git` · `make` · `jq`) 은 실패입니다
- **메뉴 막대** `swiftbar/dotfiles-update.5m.sh` — 상태 파일만 읽습니다 (네트워크 · git 없음). 손 필요 · 실패, 24시간 넘게 이어진 "받아오지 못함" (깨어난 직후 · 오프라인은 넘김), 3일 넘게 돌지 않은 자동 갱신이 있을 때만 `↓N` 을 띄우고, 없으면 아무것도 출력하지 않아 SwiftBar 가 항목을 두지 않습니다. 메뉴: 대상별 상태, "지금 업데이트" (같은 조건 — 미커밋 변경은 덮지 않음), "로그 열기", Brewfile 표시의 "확인함 (표시 지우기)"
- **장비 점검** (`machine.sh` §4) — 자동 갱신이 3일 넘게 돌지 않았거나 손 필요 · 실패 · 받아오지 못함이 3일 넘게 이어지면 WARN (주 1회 메일), 그보다 짧으면 INFO, 상태 파일이 없으면 INFO
- 잠금 (`~/.local/state/dotfiles-update/lock`) 으로 실행이 겹치지 않습니다. 로그: `~/Library/Logs/dotfiles-auto-update.log` (1MB 초과 시 `.1` 로 로테이션)
- 등록 · 해제는 다른 예약과 같이 `make sync` · `make clean`. 끄려면 `launchctl bootout gui/$(id -u)/com.socoolbear.dotfiles-auto-update` (다음 `make sync` 때 다시 등록됩니다)

저장소 안에서 끝나는 점검 (`doctor.sh --repo-only`) 은 GitHub Actions `.github/workflows/check.yml` 이 push · PR · 주 1회 (월 09:00 KST) 돌립니다. 끄려면 GitHub 저장소의 Actions 탭에서 그 workflow 를 Disable 합니다.

## oh-my-tmux 주의사항

- `tmux.conf` 는 oh-my-tmux 가 관리 (수정 금지)
- `tmux.conf.local` 만 커스터마이징
- 위치: `~/.config/tmux/` (XDG 표준)

## claude/ 하위 구성

- `claude/settings.json` — Claude Code 글로벌 설정 (hooks, 권한, 환경변수)
- 취향 규칙 (공용 글로벌 인스트럭션 `AGENTS.md` · 워크플로우 표 · 코딩 스타일 · 문서) 은 workstyle 플러그인 (socoolbear/cc-marketplace 의 `plugins/workstyle/rules/`) 으로 옮겼다. 이 장비에서는 `~/.claude/workstyle/` 가 그 체크아웃으로 가는 심링크이고, Codex (`~/.codex/AGENTS.md`) 는 그 폴더의 `AGENTS.md` 를 읽는다.
- `claude/CLAUDE.md` — 전역 지시 파일. 불러오기 줄만 둔다: `@~/.claude/workstyle/{AGENTS,workflow-table,coding-style}.md` 와 비공개 파일 `@~/.config/claude/{deploy-targets,local-rules}.md`. 경로는 홈 기준 — 상대 경로는 이 파일의 실제 위치 (dotfiles) 기준으로 풀린다
- `claude/scripts/` — 설정이 부르는 장비 접착 스크립트 (`statusline-command.sh` — status line, `tmux-claude-state.sh` — tmux 창 목록의 작업 상태 표시). 작업 훅 (계획 검증 · 질문 점검 · 멈춤 점검 · 배포 확인 등) · 에이전트 · 명령은 workstyle · deploy-guard 플러그인이 맡는다
- 플러그인 — dotfiles 에서 플러그인 (socoolbear/cc-marketplace) 으로 옮긴 장치는 `settings.json` 의 `enabledPlugins` 가 켜고, `make sync` 가 `scripts/claude-plugins-sync.sh` 로 빠진 플러그인 설치와 장비 등록 (`workstyle install` — `~/.local/bin/workstyle` · `loop-metrics`) 을 챙긴다
- `claude/docs/lessons.md` — 도구·워크플로우 전반의 교훈 (`~/.claude/docs/` 로 링크. workstyle 의 피드백 라우팅 문서가 가리킨다)

## `make backup` 의 한계

`make backup` 은 호스트 로컬 데이터 (`~/.gitconfig_local`, `~/.private-exports`, doctor 금지어 목록 `~/.config/dotfiles/sensitive-words`, 비공개 배포 분류 `~/.config/claude/deploy-targets{,.md}` (워크스페이스 repo 의 `policy/` 로 가는 심링크면 그 내용을 복사) · 배포 QA 알림 패턴 `~/.config/claude/deploy-qa-patterns`) 와 zsh, vim, idea, tmux, git, ghostty, karabiner, mise, claude-notify 설정만 백업합니다. 다음은 백업 대상이 아니므로 필요시 직접 처리:

- `~/.claude/` (settings.json 등)
