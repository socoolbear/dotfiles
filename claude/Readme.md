# claude/ 메모

## MCP
- MCP 서버는 `claude mcp add -s user` 로 등록한다 (저장 위치는 `~/.claude.json` — dotfiles 관리 밖).
  `~/.mcp.json` 은 **상위 디렉토리 프로젝트 설정** 으로 동작해서 `$HOME` 밖 (외장 볼륨 등) 에서는 서버가 하나도 안 뜨고,
  프로젝트마다 승인 프롬프트도 뜨므로 쓰지 않는다 (2026-10-09 사용자 결정).
- `server-filesystem` 은 넣지 않는다. Claude Code 는 MCP roots 를 지원해서
  **CLI 인자로 준 디렉토리를 세션 launch 디렉토리로 치환**해 버리므로 인자가 무의미하고,
  내장 도구와 범위가 겹친다. 특정 디렉토리를 열려면 `--add-dir` / `additionalDirectories`.

## 새 장비에서 따로 옮길 것
- `~/.claude/settings.local.json` (머신별 설정, dotfiles 관리 밖)
