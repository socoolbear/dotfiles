# claude/ 메모

## MCP
- MCP 서버는 `claude mcp add -s user` 로 등록한다 (저장 위치는 `~/.claude.json` — dotfiles 관리 밖).
  `~/.mcp.json` 은 **상위 디렉토리 프로젝트 설정** 으로 동작해서 `$HOME` 밖 (외장 볼륨 등) 에서는 서버가 하나도 안 뜨고,
  프로젝트마다 승인 프롬프트도 뜨므로 쓰지 않는다 (2026-10-09 사용자 결정).
- `server-filesystem` 은 넣지 않는다. Claude Code 는 MCP roots 를 지원해서
  **CLI 인자로 준 디렉토리를 세션 launch 디렉토리로 치환**해 버리므로 인자가 무의미하고,
  내장 도구와 범위가 겹친다. 특정 디렉토리를 열려면 `--add-dir` / `additionalDirectories`.

## 새 장비에서 따로 옮길 것
- `~/.config/claude/machine.json` — 장비별 Claude 설정 (dotfiles 관리 밖). `cc`·`cct` (`zsh/zshrc` 의 `claudeTeam`) 가 이 파일이 있으면 `--settings` 로 덧붙인다
  - 만들기: `mkdir -p ~/.config/claude` 후 JSON 작성. `--settings` 는 명령줄 설정이라 사용자·프로젝트 설정보다 우선하고, `enabledPlugins` 는 키 단위로 덮인다 (2.1.310 시험)
  - 회사 장비 예: `{"enabledPlugins": {"datadog@claude-plugins-official": true}}` — datadog 은 공용에서 끄고 쓰는 장비에서만 켠다 (2026-10-25 사용자 결정). `/plugin` 으로 켜면 공용 `settings.json` (심링크) 이 바뀌므로 machine.json 으로만 켠다
  - `claude` 를 직접 띄우거나 IDE 에서 띄우면 적용되지 않는다. `~/.claude/settings.local.json` 은 사용자 수준에서 읽히지 않으므로 쓰지 않는다 (2.1.310 시험)

## 스킬
- `worktree-setup` · `worktree-refresh` 는 플러그인 `worktrees` (socoolbear/cc-marketplace) 로 관리한다 (2026-10-13 사용자 결정)

## 파괴적 명령 가드 — cc-safety-net 시험 (2026-11-21 ~ 11-28)
- 권한 확인 없이 뜨는 세션에서 `rm -rf` · `git reset --hard` · force push · `git clean -f` · `git branch -D` · `git checkout --` · `find -delete` · `curl | bash` 를 PreToolUse 훅으로 막는다. 플러그인 `cc-safety-net@cc-marketplace` (kenryu42/cc-marketplace, 검토한 v2.8.1 에 고정하려고 `autoUpdate: false`). 임시 폴더 아래 `rm -rf`, `--force-with-lease`, `git worktree remove` (--force 없이) 는 통과한다
- 고른 이유: destructive_command_guard 는 라이선스가 Anthropic 과 그 대리인의 실행·분석을 금지하고, 설치 스크립트가 바이너리를 받아 `settings.json` · `.zshrc` 를 고친다. cc-safety-net 은 MIT, 의존성 없는 node 번들이고 네트워크를 쓰지 않으며, 훅이 쓰는 파일은 `~/.cc-safety-net/` 뿐이다. 분석 중 오류가 나면 막는다 (fail-closed)
- 비밀 파일 보호는 끈다 — `~/.cc-safety-net/policy.json` 에 `{"version": 1, "secret_protection": {"enabled": false}}`. 켜 두면 `.env` 읽기·수정 (`op inject` 포함) 이 막힌다. 가드가 심링크 정책 파일을 거부해 dotfiles 밖 로컬 파일로 둔다
- 새 장비: `make sync` 는 마켓플레이스를 등록하지 않으므로 먼저 `claude plugin marketplace add kenryu42/cc-marketplace` (이 명령은 `settings.json` 키 순서를 바꾸고 `autoUpdate` 를 지우니 실행 뒤 `git checkout claude/settings.json`), 그다음 `make sync`, 위 `policy.json` 작성 (폴더 700 · 파일 600)
- 알려진 문제 (v2.8.1): 현재 폴더·저장소 루트에 대한 `rm -rf` 는 `rm.git-metadata` 로 판정되지만 메시지를 만들다 오류가 나서 화면에는 `analysis.failed-closed` 로 보인다 (막히는 결과는 맞고, 기록에는 원래 규칙이 남는다). deploy-guard 와 함께 막으면 (`git push --force origin main` 등) 화면에는 deploy-guard 메시지만 보인다
- 기록: `~/.cc-safety-net/logs/<cwd>/<YYYY-MM>/<UTC 날짜>-<세션>.jsonl` 에 Bash 판정이 허용·차단 모두 남는다 (비밀 값 가림, 30일 보관, 로컬만)
- 11-28 판단: 아래로 차단 목록을 뽑아 한 건씩 "평소 하려던 일을 막았는가 (잘못 막음)" 를 본다. 잘못 막은 건이 규칙 하나에 몰리면 그 규칙만 끄고 (`policy.json` 의 `destructive_command_protection.overrides` 에 `"<규칙>": "off"`), 여러 규칙에 걸쳐 주에 3건을 넘거나 막혀서 일이 멈춘 적이 있으면 뺀다
  ```bash
  jq -r 'select(.decision=="deny" and .ts>="2026-11-20T23:00" and (.cwd // "" | test("/scratchpad/") | not)) | [.ts[0:16], .ruleId, .cwd, .command[0:80]] | @tsv' ~/.cc-safety-net/logs/*/*/*.jsonl
  ```
- 끄기: `settings.json` 의 `"cc-safety-net@cc-marketplace"` 를 `false` 로 바꾼다 (새 세션부터). 완전히 빼려면 그 줄과 `extraKnownMarketplaces.cc-marketplace` 를 지우고 `claude plugin uninstall cc-safety-net@cc-marketplace` · `claude plugin marketplace remove cc-marketplace` (둘 다 `settings.json` 을 다시 쓰니 뒤에 diff 확인), `rm -rf ~/.cc-safety-net`
