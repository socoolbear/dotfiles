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
