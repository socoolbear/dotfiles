# Migration Guide
## Plugin 
- ripgrep 설치 확인
- oh-my-claude
- claude-mem
- anthropics/skills
- claude official plugin

## Config
- ~/.claude/* 내용들 이관
  - settings.local.json 
  - ~~plansDirectory 설정~~ (완료 — `claude/settings.json`)

## MCP (`claude/.mcp.json` → `~/.mcp.json`)
- `~/.mcp.json` 은 **상위 디렉토리 프로젝트 설정** 으로 동작한다. 즉 `$HOME` 아래 경로에서만 서버가 뜨고,
  외장 볼륨 등 `$HOME` 밖에서 작업하면 서버가 하나도 안 뜬다. 프로젝트마다 승인 프롬프트도 뜬다.
- 전 프로젝트에 확실히 띄우려면 `claude mcp add -s user` (저장 위치는 `~/.claude.json` — dotfiles 관리 밖).
- `server-filesystem` 은 넣지 않는다. Claude Code 는 MCP roots 를 지원해서
  **CLI 인자로 준 디렉토리를 세션 launch 디렉토리로 치환**해 버리므로 인자가 무의미하고,
  내장 Read/Write/Glob/Grep 과 범위가 겹친다. 특정 디렉토리를 열려면 `--add-dir` / `additionalDirectories`.
- IDEA claude code plugin 
  - 프로젝트 별 task id  다르게 가져가는 방법 :
    ```aiignore
    CLAUDE_CODE_TASK_LIST_ID=$(basename "$PWD") claude --dangerously-skip-permissions
    ```