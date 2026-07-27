# Coding Style Rules

> **상위 원칙: 주변 코드의 관용구를 먼저 따른다.**
> 아래는 새 코드를 쓰거나 따를 관용구가 없을 때의 기본값이다. 기존 코드가 다른 방식으로 일관돼 있으면
> 그쪽을 따르고, 이 문서를 근거로 기존 코드를 고치지 않는다.
>
> 린터·포매터가 **자동 교정하는** 항목은 여기 쓰지 않는다. 도구가 잡게 둔다.

## General Principles

- **Early return**: 중첩 조건문 대신 조기 반환 선호
- **빈 줄 추가**: 변수 선언과 제어문/함수 호출 사이에 빈 줄 (포매터가 넣어주지 않는 부분이라 명시)
- **Immutability**: 가변 객체/클래스보다 불변 패턴 선호
- **Single responsibility**: 함수는 하나의 일만

## Naming Conventions

- **함수명**: 동사 사용 (예: `createSymlink`, `backupFile`, `installPackage`)
- **변수명**: 명사 사용 (예: `dotfilesPath`, `targetDir`, `configFile`)

## Shell Script Specific

- `set -e` 또는 `set -euo pipefail` 사용
- 변수는 `${VAR}` 형태로 중괄호 사용
- 문자열 비교시 `[[` 사용 (`[` 대신)

## Makefile Specific

- `.PHONY` 타겟 명시
- 조건부 실행은 `[ -L ... ] ||` 또는 `[ -d ... ] ||` 패턴 사용
- 에러 무시가 필요한 명령은 `-` 접두사 사용
