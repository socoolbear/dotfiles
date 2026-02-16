# Coding Style Rules

## General Principles

- **Early return**: 중첩 조건문 대신 조기 반환 사용
- **빈 줄 추가**: 변수 선언과 제어문/함수 호출 사이에 빈 줄 추가
- **Immutability**: 가변 객체/클래스 사용 지양, 불변 패턴 선호
- **Single responsibility**: 함수는 단일 책임 원칙 준수

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
