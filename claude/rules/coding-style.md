# Coding Style Rules

> **상위 원칙: 주변 코드의 관용구를 먼저 따른다.**
> 아래는 새 코드를 쓰거나 따를 관용구가 없을 때의 기본값이다. 기존 코드가 다른 방식으로 일관돼 있으면
> 그쪽을 따르고, 이 문서를 근거로 기존 코드를 고치지 않는다.
>
> 린터·포매터가 **자동 교정하는** 항목은 여기 쓰지 않는다. 도구가 잡게 둔다.

## General Principles

- **Early return**: 중첩 조건문 대신 조기 반환 선호
- **빈 줄 (문 사이)**: 문을 다섯 종류로 나눠 같은 종류끼리는 붙이고, 종류가 바뀌는 곳에 빈 줄 하나 (포매터가 넣어주지 않는 부분이라 명시)
  - 종류: 선언·대입 (`?: return` 으로 끝나는 선언 포함) / 제어 블록 (`if` · `when`·`switch` · `for` · `while` · `try`, `repeat(n) { … }`) / 실행 (결과를 쓰지 않는 호출, 람다를 받는 호출, 시험에서 시험 대상의 결과를 받는 선언 포함. 기대값 선언은 선언) / 검증 (시험의 `assert*` · `verify`) / 종료 (`return` · `throw`)
  - 선언끼리, 연속된 실행끼리, 연속된 검증끼리는 붙인다. 제어 블록은 블록마다 띄운다
  - 블록의 첫 문 앞 · 마지막 문 뒤에는 빈 줄을 두지 않는다
  ```ts
  const operator = requireOperator(context);
  const cached = await this.redis.getBuffer(key);

  if (!cached) {
    throw new NotFound(key);
  }

  this.audit.record(operator, key);

  return decode(cached);
  ```
- **try/catch 중첩 금지**: `try` 블록 안에 또 `try` 가 필요하면 안쪽을 private 함수로 추출한다
- **복잡한 조건은 함수로 추출**: `if` 조건이 `&&` · `||` 로 세 개 이상 이어지면 의도가 드러나는 이름의 함수 (`isValidLoginToken(...)`) 로 뺀다
- **Immutability**: 가변 객체/클래스보다 불변 패턴 선호
- **Single responsibility**: 함수는 하나의 일만

## Naming Conventions

- **함수명**: 동사 사용 (예: `createSymlink`, `backupFile`, `installPackage`)
- **변수명**: 명사 사용 (예: `dotfilesPath`, `targetDir`, `configFile`)
- **한 글자 변수명 금지**: `v` · `r` · `e` 대신 담긴 값을 말하는 이름 (`cached`, `response`, `error`). 반복문 인덱스 `i` · `j` 만 예외

## Shell Script Specific

- `set -e` 또는 `set -euo pipefail` 사용
- 변수는 `${VAR}` 형태로 중괄호 사용
- 문자열 비교시 `[[` 사용 (`[` 대신)

## Makefile Specific

- `.PHONY` 타겟 명시
- 조건부 실행은 `[ -L ... ] ||` 또는 `[ -d ... ] ||` 패턴 사용
- 에러 무시가 필요한 명령은 `-` 접두사 사용
