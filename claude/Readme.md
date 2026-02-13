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
  - plansDirectory 설정
- IDEA claude code plugin 
  - 프로젝트 별 task id  다르게 가져가는 방법 :
    ```aiignore
    CLAUDE_CODE_TASK_LIST_ID=$(basename "$PWD") claude --dangerously-skip-permissions
    ```