# 디렉토리별 GitHub 계정 분리

`~/code/side/` 아래에서는 side 계정, 그 밖에서는 기본 계정이 자동으로 쓰이도록 한 설정.
git 작성자·커밋 서명·SSH 인증·`gh` CLI 네 가지가 모두 디렉토리 기준으로 갈린다.

## 현재 구성

| | 기본 계정 | side 계정 |
|---|---|---|
| GitHub | `socoolbear` | `<side 계정>` |
| 적용 범위 | `~/code/side/` 밖 전부 | `~/code/side/` 아래 모든 repo·worktree |
| 작성자 | `~/.gitconfig_local` `[user]` | `~/.config/git/side.gitconfig` `[user]` |
| SSH·서명 키 | 1Password "개인" vault (기본 키) | 1Password "Side" vault (side 키) |
| SSH 접속 | `github.com` 그대로 | `github-side` 별칭으로 자동 치환 |
| `gh` CLI | Active 계정 | `direnv` 가 `GH_TOKEN` 주입 |

## 동작 원리 (파일 7개)

```
~/.gitconfig_local                  기본 [user] + signingkey, includeIf → side.gitconfig, allowedSignersFile
~/.config/git/side.gitconfig        side [user] + signingkey, url.insteadOf → github-side
~/.config/git/allowed_signers       두 계정 이메일 ↔ 공개키 (로컬 서명 검증용)
~/.ssh/config                       Host github-side → side.pub 만 사용 (IdentitiesOnly)
~/.ssh/side.pub                     side 공개키 (비밀키는 1Password 에만 있음)
~/code/side/.envrc                  export GH_TOKEN=$(gh auth token -u <side 계정>)
~/.config/1Password/ssh/agent.toml  vault 순서: "개인" → "Side" (기본 계정 키가 먼저 제공되도록)
```

흐름:

1. `~/code/side/**` 에서 git 실행 → `includeIf "gitdir:~/code/side/"` 가 `side.gitconfig` 를 읽음
2. `side.gitconfig` 의 `url."git@github-side:".insteadOf = git@github.com:` 가 remote 주소를 치환
3. `~/.ssh/config` 의 `Host github-side` 가 `IdentitiesOnly yes` + `side.pub` 로 side 키만 agent 에 요청
4. 커밋 서명은 `user.signingkey` 문자열로 1Password `op-ssh-sign` 이 키를 찾음 (파일 불필요)
5. `gh` 는 디렉토리를 모르므로 `direnv` 가 `.envrc` 로 `GH_TOKEN` 을 넣어 계정을 고정

## 새 계정 추가 절차 (예: work)

변수만 바꿔서 순서대로 실행한다.

```sh
ACCOUNT=work                        # 별칭·파일명에 쓰는 짧은 이름
DIR=~/code/work                     # 이 아래에서 적용
GH_USER=<github-username>
NAME="<커밋 작성자 이름>"
EMAIL="<커밋 이메일>"
```

### 1. 1Password 에서 SSH 키 생성

- New Item → SSH Key → Generate (Ed25519) → 제목 예: `GitHub ${ACCOUNT}`
- 키가 든 vault 가 `agent.toml` 에 등록돼 있어야 한다. 새 vault 면 **기본 계정 vault 뒤에** 추가:

  ```toml
  [[ssh-keys]]
  vault = "개인"        # 기본 계정 — 반드시 첫 번째

  [[ssh-keys]]
  vault = "Work"
  ```

### 2. 공개키를 로컬 파일로

```sh
SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
SSH_AUTH_SOCK="$SOCK" ssh-add -L                       # 목록에서 새 키 확인
SSH_AUTH_SOCK="$SOCK" ssh-add -L | grep '<키 일부>' > ~/.ssh/${ACCOUNT}.pub
chmod 644 ~/.ssh/${ACCOUNT}.pub
PUBKEY=$(cut -d' ' -f1,2 ~/.ssh/${ACCOUNT}.pub)
```

### 3. GitHub 에 키 등록 (웹)

해당 계정 → Settings → SSH and GPG keys → New SSH key 를 **두 번**:

| Key type | 용도 |
|---|---|
| Authentication Key | push / pull |
| Signing Key | 커밋 "Verified" 배지 |

### 4. SSH 별칭

`~/.ssh/config` 에 추가:

```
Host github-${ACCOUNT}
    HostName github.com
    User git
    IdentityFile ~/.ssh/${ACCOUNT}.pub
    IdentitiesOnly yes
```

### 5. git 설정

```sh
cat > ~/.config/git/${ACCOUNT}.gitconfig <<EOF
[user]
    name = ${NAME}
    email = ${EMAIL}
    signingkey = ${PUBKEY}

[url "git@github-${ACCOUNT}:"]
    insteadOf = git@github.com:
EOF

cat >> ~/.gitconfig_local <<EOF

[includeIf "gitdir:${DIR}/"]
    path = ~/.config/git/${ACCOUNT}.gitconfig
EOF

echo "${EMAIL} ${PUBKEY}" >> ~/.config/git/allowed_signers
```

### 6. gh CLI

```sh
gh auth login                       # 브라우저에서 새 계정으로 로그인. "Upload SSH key?" 는 Skip
gh auth switch -u socoolbear        # 기본 계정을 Active 로 되돌림

cat > ${DIR}/.envrc <<EOF
export GH_TOKEN="\$(gh auth token -u ${GH_USER})"
EOF
direnv allow ${DIR}
```

### 7. 확인

```sh
ssh -T git@github-${ACCOUNT}                       # Hi <GH_USER>!
ssh -T git@github.com                              # Hi socoolbear!  (기본 계정 그대로인지)

cd ${DIR}/<어떤 repo>
git config user.email                              # EMAIL
git remote -v                                      # git@github-${ACCOUNT}:... 로 치환됐는지
git commit --allow-empty -m tmp
git log -1 --format='%G? %GS'                      # G <EMAIL>
git push --dry-run origin HEAD                     # 인증 통과
git reset --hard HEAD~1
gh api user --jq .login                            # GH_USER

cd ~ && gh api user --jq .login                    # socoolbear
```

## 새 장비에서 복원

오늘 만든 파일은 모두 dotfiles **밖**에 있다 (계정 연결 정보라 공개 저장소에 넣지 않음). `make sync` 로는 복원되지 않는다.

| 누가 | 무엇 |
|---|---|
| `make sync` | `~/.gitconfig` (gpgsign · op-ssh-sign · `include ~/.gitconfig_local`), zshrc 의 `direnv hook`, Brewfile 로 `direnv` 설치 |
| 1Password Secure Note | 아래 7개 파일 — `Side` vault 의 `github-accounts-local-files` |
| 건너뜀 | 1Password SSH 키 생성 · GitHub 키 등록 (이미 돼 있음) |

```sh
# 1. 1Password 앱 설치 → Settings → Developer → SSH agent 켜기
# 2. dotfiles
make sync
# 3. 로컬 파일 7개 복원 (~/.gitconfig_local, ~/.config/git/*, ~/.ssh/config, ~/.ssh/side.pub, ~/code/side/.envrc, agent.toml)
mkdir -p ~/code/side
op read 'op://Side/github-accounts-local-files/BUNDLE' | base64 -d | tar xzf - -C ~
direnv allow ~/code/side
# 4. gh 두 계정 로그인 ("Upload SSH key?" 는 Skip)
gh auth login && gh auth login
gh auth switch -u socoolbear
# 5. 확인 — 위 "7. 확인" 절
```

파일을 고쳤으면 Secure Note 도 갱신한다:

```sh
cd ~ && op item edit github-accounts-local-files --vault Side "BUNDLE[text]=$(
  tar czf - .gitconfig_local .config/git/side.gitconfig .config/git/allowed_signers \
    .ssh/config .ssh/side.pub code/side/.envrc .config/1Password/ssh/agent.toml | base64)" >/dev/null
```

## 자주 틀리는 것

- **`insteadOf` 의 콜론**: `[url "git@github-side:"]` — 끝에 `:` 가 없으면 `git@github-sideorg/repo` 로 붙어서 접속 불가
- **`IdentitiesOnly yes` 는 별칭 Host 에만**: `Host *` 에 넣으면 기본 계정 접속이 깨진다. 이게 없으면 agent 가 키를 순서대로 다 시도해 첫 번째 유효 키 (기본 계정) 로 붙는다
- **`.pub` 파일은 필요하다**: 비밀키는 1Password 가 갖고 있지만, ssh 는 "어느 키를 쓸지" 를 공개키 파일로 지목한다. 커밋 서명은 gitconfig 에 공개키 문자열을 직접 적어 파일이 필요 없다
- **`includeIf` 경로 끝 `/`**: `gitdir:~/code/side/` — 없으면 `~/code/side2` 같은 곳도 매칭된다
- **`~/code/side/` 안에서 `gh auth switch` 는 먹지 않는다**: `GH_TOKEN` 환경변수가 우선. 의도된 동작
- **`git log --show-signature` 가 `N`**: 서명이 없거나 (설정 전 커밋) `allowed_signers` 에 그 이메일이 없는 것. GitHub "Verified" 와는 무관
- **한 SSH 키를 두 계정에 등록할 수 없다**: GitHub 가 거부한다. 계정마다 키를 따로 만든다
