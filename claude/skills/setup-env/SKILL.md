---
name: setup-env
description: dotfiles 저장소의 Makefile 을 활용해 macOS 환경을 세팅한다. 사용자가 "환경 세팅", "새 장비 셋업", "dotfiles 동기화", "make update", "brew 앱 설치" 같이 명시적으로 요청할 때만 트리거.
---

# Setup Env (dotfiles)

`~/.dotfiles` 의 Makefile 을 진입점 하나로 묶어, 사용자 의도(새 장비 / 일상 동기화 / 부분 작업)에 따라 적절한 타겟을 분기 실행하고 자동화 불가능한 후속 수동 작업까지 안내한다.

## 언제 사용하는가

사용자가 **명시적으로** 환경 세팅 / 동기화를 요청할 때만 실행한다.

다음과 같은 표현이 신호다:
- "환경 세팅", "새 장비 셋업", "dotfiles 동기화", "dotfiles 적용"
- "make update 해줘", "make fresh 돌려줘", "brew 앱 설치"
- "심링크 다시 걸어줘", "이 머신에 dotfiles 깔아줘"

모호한 요청 ("정리 좀 해줘", "셋업 좀 봐줘") 에서는 직접 실행하지 말고 의도를 먼저 확인한다.

## 워크플로우

### 1. 사전 확인 (병렬 실행)

세 가지를 한 메시지에서 병렬 실행한다:

```bash
pwd                                            # 현재 위치
ls -la "$HOME/.dotfiles" 2>/dev/null | head    # repo 존재 여부
test -x "$(command -v brew)" && brew --version || echo "no-brew"
```

확인 사항:
- `~/.dotfiles` 가 없으면 → **새 장비 부트스트랩** 분기 (아래 A)
- `~/.dotfiles` 가 있고 git 작업 트리가 dirty 하면 → 사용자에게 알리고 commit/stash 권장 (동기화 진행 가능하지만 의도치 않은 변경 위험 안내)
- Homebrew 가 없으면 → bootstrap.sh 가 설치하므로 분기 A 또는 B 안내

### 2. 의도 분기 (AskUserQuestion)

사용자 메시지에서 의도가 명확하면 (예: "make update 해줘") 곧장 해당 분기로 진행. 모호하면 다음 4 분기 중 하나를 묻는다 (single-select):

| 분기 | 라벨 | 설명 | 명령 |
|------|------|------|------|
| A | 새 장비 부트스트랩 | Xcode CLT / Homebrew 부터 전부 | `bash ~/.dotfiles/bootstrap.sh` |
| B | 새 장비 (Brew 있음) | 자동화 단계 일괄 실행 | `make -C ~/.dotfiles fresh` |
| C | 일상 동기화 (권장 기본값) | brew + sync 만 빠르게 | `make -C ~/.dotfiles update` |
| D | 부분 작업 | 특정 타겟만 골라 실행 | 추가 질문 |

D 를 선택하면 두 번째 AskUserQuestion 으로 다음 중 1 개 이상 (multiSelect):

- `brew` — Brewfile (코어 CLI)
- `brew-apps` — Brewfile.apps (GUI 앱, App Store 항목 있으면 사전 로그인 필요)
- `sync` — 심링크만 재생성
- `mise` — Node/Go 등 글로벌 런타임
- `npm` — NPM globals (LSP, prettier 등)
- `macos` — macOS 시스템 기본값
- `backup` — 호스트 로컬 데이터 백업 (`~/backup_dotfiles/`)

### 3. 실행

선택된 타겟을 Bash 로 실행한다. `cd` 로 옮겨다니지 말고 `make -C ~/.dotfiles <target>` 패턴을 우선 (현재 작업 디렉토리에 영향 안 주기).

```bash
make -C "$HOME/.dotfiles" update
```

bootstrap.sh 는 sudo 비밀번호와 Xcode CLT GUI 설치 창 (Apple 다이얼로그) 을 요구할 수 있으므로, 사용자에게 **터미널을 직접 보고 있어야 함** 을 미리 알린다. 출력이 길어지면 그대로 사용자에게 보여주고, 비파괴적 경고 (예: `brew bundle` 의 cask up-to-date 메시지) 는 무시한다.

**실패 시**: 멈추고 진단. `make sync` 가 `~/.gitconfig 가 실파일입니다` 에러로 중단되면 안내된 마이그레이션 명령 (`mv ~/.gitconfig ~/.gitconfig_local && make sync`) 을 사용자 확인 후 실행.

### 4. 후속 수동 작업 안내

자동화로 처리 불가능한 항목을 체크리스트로 출력. 분기 A/B (새 장비) 에서는 전체, 분기 C (일상 동기화) 에서는 생략 가능:

```markdown
## 후속 수동 작업 체크리스트

- [ ] `~/.gitconfig_local` 작성 — 이름/이메일, 호스트별 includeIf
      참고: docs/install-note.md 의 Git 섹션
- [ ] `~/.private-exports` 작성 — `cp zsh/private.export.example ~/.private-exports` 후 토큰 입력 (NTFY/EXA/GitHub 등). zshrc 가 자동 source.
- [ ] App Store 로그인 → `make brew-apps` (mas 항목용)
- [ ] 1Password 로그인 + SSH 키 동기화 (`brew install 1password-cli && op signin`)
- [ ] JetBrains / Alfred / Obsidian 등 GUI 앱 라이센스/설정 복원
- [ ] (선택) `~/.zsh_history` 마이그레이션 — atuin 권장, docs/install-note.md 의 "홈 디렉토리에서 옮길 파일" 섹션 참조
- [ ] GPG 키 없으면 `~/.gitconfig_local` 에 `[commit] gpgsign = false` 추가
- [ ] 새 셸 시작: `exec zsh`
```

`docs/install-note.md` 가 단일 진실 출처이므로 **새 항목을 임의로 추가하지 말고**, 항목이 늘면 `install-note.md` 에 먼저 기록할 것을 사용자에게 권한다.

### 5. 검증

마지막으로 심링크 정상 여부를 확인:

```bash
ls -la ~/.claude/ ~/.config/mise/ ~/.zshrc 2>&1 | head -20
make -C ~/.dotfiles help     # 사용 가능 타겟 한 번 더 보여주기 (참고용)
```

## 주의사항

- **`make clean` 절대 자동 호출 금지** — 모든 dotfiles 심링크가 제거된다. 사용자가 명시적으로 `make clean` 또는 "심링크 다 지워줘" 라고 요청한 경우에만 실행하고, 실행 전 한 번 더 확인한다.
- **`make backup` 은 새 장비 셋업 *전* (구 장비에서)** 실행해야 의미 있다. 새 장비에서 셋업 *후* 호출하면 빈 `~/backup_dotfiles/` 만 만들어진다.
- **`brew-apps` 의 `mas` 항목**은 App Store 로그인이 안 되어 있으면 조용히 실패한다. 출력에서 `mas` 관련 에러가 보이면 사용자에게 App Store 로그인 후 `make brew-apps` 재실행을 안내.
- **bootstrap.sh 는 sudo 와 GUI 다이얼로그**를 요구한다. CI/원격 세션에서 호출하지 말 것 (Xcode CLT 설치 창이 데스크톱에 뜬다).
- **글로벌 규칙 우선** — `~/.claude/AGENTS.md` 의 한국어/존댓말 규칙을 모든 안내 메시지에 적용. 영어와 한국어 혼용 시 띄어쓰기 추가 (예: "Brewfile 에서").
