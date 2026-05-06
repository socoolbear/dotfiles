# 프로젝트별 `.env` 관리 (1Password CLI)

```shell
brew install 1password-cli
op signin
```

## 새 환경 파일 등록

```shell
op item create --vault="my-vault" --category="Secure Note" \
  --title="myproject-env" \
  ENV_CONTENT="$(cat .env)"
```

## 기존 환경 파일 가져오기

```shell
op item get "myproject-env" --vault="my-vault" --format json --reveal \
  | jq -r '.fields[] | select(.label=="ENV_CONTENT") | .value' > .env
```

## 환경 파일 갱신

```shell
op item edit "myproject-env" --vault="my-vault" \
  ENV_CONTENT="$(cat .env)"
```
