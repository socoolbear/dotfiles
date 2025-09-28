# Apps
- slack, k9s, forti-client, jetbrains, notion, obsidian, postman, zoom,
- rectangle, alfred, 1password, discord, google-chrome, figma,
- claude code, claude desktop, gpt desktop
- docker, runcat
- kakao Talk

# Tasks
- copy .zsh_history from old
- git
    - set global name, email
    - split account  : .gitconfig > IncludeIf
- alfred : plugin setting
- obsidean : valute setting
- forti-client : vpn setting
- jetbrains : terminal font - 13, jetbrains mono
- By Projects
  - .env files
```shell
brew install 1password-cli
op signin
```
```shell
# create env file in 1password
op item create --vault="my-vault" --category="Secure Note" --title="myproject-env" ENV_CONTENT="$(cat .env)"
```
```shell
# get env file from 1password
op item get "myproject-env" --vault="my-vault" --format json --reveal \
| jq -r '.fields[] | select(.label=="ENV_CONTENT") | .value' > .env
```
```shell
# update env file to 1password
op item edit "myproject-env" --vault="my-vault" ENV_CONTENT="$(cat .env)"
```
  - github copilot : cp [copilot instructions](/copilot)  to {project root}/.github/
  - claude
      - claude-desktop : setting sync
      - claude-code : setting sync
      - [super claude](https://github.com/SuperClaude-Org/SuperClaude_Framework)
      - [claude-code-requirements-builder](https://github.com/rizethereum/claude-code-requirements-builder)
- jetbrains ide 단축키 충돌 방지 (cmd + shift + A)
  - 설정 > 키보드 단축키 > 서비스 > 텍스트 > 터미널에서 man 페이지 인덱스 검색 off