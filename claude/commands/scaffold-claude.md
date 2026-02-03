---
description: 어떤 프로젝트에서든 일관된 .claude/ 디렉토리 구조와 AGENTS.md를 세팅하는 범용 명령어
---

# 프로젝트 초기화 (.claude/ + AGENTS.md)

현재 프로젝트를 AI-ready 상태로 만들기 위해 `.claude/` 디렉토리 구조와 `AGENTS.md` 를 자동으로 생성합니다.

## 명령어가 수행할 작업

### 1. 프로젝트 분석
- 프로젝트 언어/프레임워크 감지 (package.json, pyproject.toml, Cargo.toml, go.mod 등)
- 디렉토리 구조 분석
- 빌드 시스템 감지 (Makefile, npm scripts, pytest, cargo 등)

### 2. `.claude/` 디렉토리 구조 생성

```
.claude/
├── settings.local.json  # 로컬 설정 (plansDirectory 등)
├── rules/           # 항상 적용되는 규칙
│   └── coding-style.md
├── commands/        # 프로젝트 전용 슬래시 명령어
├── plans/           # 작업 계획서 (.gitignore)
├── agents/          # 커스텀 에이전트 정의
└── skills/          # 워크플로우/도메인 지식
```

### 3. AGENTS.md 생성

프로젝트에 맞는 `AGENTS.md` 를 자동 생성합니다:
- 프로젝트 개요
- 프로젝트 구조
- 명령어 (빌드, 테스트, 실행)
- 아키텍처
- 코딩 스타일 가이드라인
- AI 응답 가이드라인

### 4. CLAUDE.md 참조 파일 생성

`CLAUDE.md` 파일을 `AGENTS.md`를 참조하는 형태로 생성합니다:

```markdown
# Reference
@AGENTS.md
```

### 5. `.gitignore` 업데이트

`.claude/plans/` 디렉토리를 제외 목록에 추가합니다.

### 6. 기본 Rules 파일 생성

`coding-style.md` 파일을 생성하여 프로젝트 언어에 맞는 코딩 스타일 가이드를 작성합니다.

---

## 실행 워크플로우

### Step 1: 프로젝트 분석 (explore 에이전트)

explore 에이전트를 사용하여 다음 정보를 수집합니다:

**분석 항목:**
1. **언어/프레임워크 감지**
   - JavaScript/TypeScript: `package.json`, `tsconfig.json`
   - Python: `pyproject.toml`, `setup.py`, `requirements.txt`
   - Rust: `Cargo.toml`
   - Go: `go.mod`
   - 기타 언어

2. **프로젝트 구조**
   - 주요 디렉토리 구조 (src, tests, docs 등)
   - 설정 파일 위치

3. **빌드 시스템**
   - npm scripts (package.json)
   - Makefile
   - pytest, cargo, go test 등

**explore 에이전트 호출 예시:**
```typescript
Task(
  subagent_type="oh-my-claudecode:explore",
  model="haiku",
  prompt="Analyze this project and identify:\n1. Language and framework\n2. Main directory structure\n3. Build and test commands\n4. Configuration file locations"
)
```

### Step 2: 기존 파일 확인

- `.claude/` 디렉토리가 이미 존재하는지 확인
- `AGENTS.md` 파일이 이미 존재하는지 확인
- 존재하는 경우 사용자에게 덮어쓸지 물어보기

### Step 3: `.claude/` 디렉토리 구조 생성

```bash
mkdir -p .claude/rules
mkdir -p .claude/commands
mkdir -p .claude/plans
mkdir -p .claude/agents
mkdir -p .claude/skills
```

### Step 4: `settings.local.json` 생성

`.claude/settings.local.json` 파일을 생성하여 로컬 설정을 정의합니다:

```json
{
  "plansDirectory": ".claude/plans"
}
```

**주의사항:**
- 이 파일은 프로젝트별 로컬 설정을 담습니다
- `plansDirectory`는 Claude Code가 계획 파일을 저장할 위치를 지정합니다
- 이 파일은 git에 커밋되어 팀원들과 공유됩니다

### Step 5: `AGENTS.md` 생성

프로젝트 분석 결과를 바탕으로 맞춤형 `AGENTS.md` 생성:

```markdown
# AGENTS.md

> AI 에이전트가 이 저장소를 이해하고 작업하기 위한 상세 가이드

## 프로젝트 개요

[프로젝트 설명 - explore 에이전트 분석 결과 기반]

## 프로젝트 구조

[디렉토리 구조 테이블 - explore 에이전트 분석 결과 기반]

## 명령어

### 빌드
[빌드 명령어 - 감지된 빌드 시스템 기반]

### 테스트
[테스트 명령어 - 감지된 테스트 프레임워크 기반]

### 실행
[실행 명령어]

## 아키텍처

[주요 아키텍처 패턴 및 구조 설명]

## 코딩 스타일 가이드라인

### 일반 원칙

- **Early return**: 중첩 조건문 대신 조기 반환 사용
- **빈 줄**: 변수 선언과 제어문/함수 호출 사이에 빈 줄 추가
- **Immutability**: 가변 객체/클래스 사용 지양
- **Single responsibility**: 함수는 단일 책임 원칙 준수

### 네이밍

- **함수명**: 동사 사용
- **변수명**: 명사 사용

### [언어별 특정 스타일]

[감지된 언어에 맞는 코딩 스타일]

## AI 응답 가이드라인

### 언어

- **한국어**로 응답 (가능한 한)
- **Git 커밋 메시지**도 한국어로 작성
- 영어와 한국어 혼용 시 **띄어쓰기** (예: "Dockerfile 에서" O, "Dockerfile에서" X)

### 작업 완료 체크리스트

작업 완료 시 다음 항목을 확인합니다:

- [ ] 요청된 모든 변경사항이 반영되었는가?
- [ ] 빌드가 정상 동작하는가?
- [ ] 테스트가 통과하는가?
- [ ] 기존 기능이 영향받지 않았는가?

## 관련 파일

- `CLAUDE.md`: AGENTS.md 참조 파일
- `AGENTS.md`: AI 에이전트 상세 가이드 (이 파일)
```

### Step 6: `CLAUDE.md` 참조 파일 생성

`CLAUDE.md` 파일을 생성하여 `AGENTS.md`를 참조하도록 합니다:

```markdown
# Reference
@AGENTS.md
```

**설명:**
- `CLAUDE.md`는 Claude Code가 기본으로 읽는 파일입니다
- `@AGENTS.md` 구문으로 실제 가이드 내용을 참조합니다
- 모든 상세 정보는 `AGENTS.md`에 집중하여 관리합니다

### Step 7: `coding-style.md` 생성

`.claude/rules/coding-style.md` 파일을 생성하여 감지된 언어에 맞는 코딩 스타일 가이드 작성.

**언어별 템플릿:**

**TypeScript/JavaScript:**
```markdown
# Coding Style Rules

## General Principles

- **Early return**: 중첩 조건문 대신 조기 반환 사용
- **빈 줄 추가**: 변수 선언과 제어문/함수 호출 사이에 빈 줄 추가
- **Immutability**: 가변 객체/클래스 사용 지양, 불변 패턴 선호
- **Single responsibility**: 함수는 단일 책임 원칙 준수

## Naming Conventions

- **함수명**: 동사 사용 (예: `createUser`, `fetchData`, `validateInput`)
- **변수명**: 명사 사용 (예: `userData`, `config`, `result`)

## TypeScript Specific

- Nullish coalescing: `??` 사용 (`||` 대신)
- Optional chaining: `?.` 적극 활용
- Type 정의는 `interface` 우선 (확장 가능성 고려)
- `any` 사용 지양
```

**Python:**
```markdown
# Coding Style Rules

## General Principles

- **Early return**: 중첩 조건문 대신 조기 반환 사용
- **빈 줄 추가**: 변수 선언과 제어문/함수 호출 사이에 빈 줄 추가
- **Immutability**: 가변 객체 사용 지양, 불변 패턴 선호
- **Single responsibility**: 함수는 단일 책임 원칙 준수

## Naming Conventions

- **함수명**: snake_case, 동사 사용 (예: `create_user`, `fetch_data`)
- **변수명**: snake_case, 명사 사용 (예: `user_data`, `config`)
- **클래스명**: PascalCase (예: `UserManager`, `DataProcessor`)

## Python Specific

- Type hints 적극 활용
- f-string 사용 (format() 대신)
- List comprehension 적절히 사용
- Context manager (with) 사용
```

**Rust:**
```markdown
# Coding Style Rules

## General Principles

- **Early return**: 중첩 조건문 대신 조기 반환 사용
- **빈 줄 추가**: 변수 선명과 제어문/함수 호출 사이에 빈 줄 추가
- **Immutability**: `mut` 최소화
- **Single responsibility**: 함수는 단일 책임 원칙 준수

## Naming Conventions

- **함수명**: snake_case, 동사 사용
- **변수명**: snake_case, 명사 사용
- **타입명**: PascalCase
- **상수명**: SCREAMING_SNAKE_CASE

## Rust Specific

- `unwrap()` 사용 지양, `?` 또는 `match` 사용
- Ownership 명확히 표현
- `Clone` 최소화
```

### Step 8: `.gitignore` 업데이트

`.gitignore` 파일에 `.claude/plans/` 추가:

```bash
# Claude Code 계획서 (로컬 전용)
.claude/plans/
```

**주의사항:**
- `.gitignore` 파일이 없으면 생성
- 이미 존재하는 경우 중복 체크 후 추가

### Step 9: 검증 및 요약

생성된 파일들을 확인하고 사용자에게 요약 보고:

```markdown
## 프로젝트 초기화 완료

### 생성된 구조

```
.claude/
├── settings.local.json      ✅ 생성됨
├── rules/
│   └── coding-style.md      ✅ 생성됨
├── commands/                ✅ 생성됨
├── plans/                   ✅ 생성됨 (.gitignore 추가)
├── agents/                  ✅ 생성됨
├── skills/                  ✅ 생성됨
CLAUDE.md                    ✅ 생성됨 (AGENTS.md 참조)
AGENTS.md                    ✅ 생성됨
.gitignore                   ✅ 업데이트됨
```

### 감지된 프로젝트 정보

- **언어**: [감지된 언어]
- **프레임워크**: [감지된 프레임워크]
- **빌드 시스템**: [감지된 빌드 시스템]

### 다음 단계

1. `AGENTS.md` 를 검토하고 프로젝트에 맞게 수정
2. `.claude/rules/coding-style.md` 를 팀 컨벤션에 맞게 조정
3. 필요시 `.claude/commands/` 에 프로젝트 전용 슬래시 명령어 추가
```

---

## 에러 처리

### 기존 파일 존재

기존 `.claude/` 디렉토리나 `AGENTS.md` 가 존재하는 경우:

```
⚠️ 다음 파일/디렉토리가 이미 존재합니다:
- .claude/
- AGENTS.md

덮어쓰시겠습니까? (y/N)
```

사용자가 'N' 을 선택하면 작업 중단.

### 프로젝트 언어 미감지

프로젝트 언어를 감지하지 못한 경우:

```
⚠️ 프로젝트 언어를 자동 감지하지 못했습니다.
사용하는 언어를 선택해주세요:

1. TypeScript/JavaScript
2. Python
3. Rust
4. Go
5. 기타
```

---

## 사용 예시

### 사용법

프로젝트 루트에서 다음 명령어 실행:

```
/scaffold-claude
```

또는

```
이 프로젝트를 AI-ready 상태로 초기화해줘
```

### 실행 결과

```
프로젝트 분석 중...

감지된 정보:
- 언어: TypeScript
- 프레임워크: React
- 빌드 시스템: npm (vite)
- 테스트: vitest

.claude/ 디렉토리 구조 생성 중...
✅ .claude/rules/ 생성
✅ .claude/commands/ 생성
✅ .claude/plans/ 생성
✅ .claude/agents/ 생성
✅ .claude/skills/ 생성

settings.local.json 생성 중...
✅ .claude/settings.local.json 생성 완료

AGENTS.md 생성 중...
✅ AGENTS.md 생성 완료

CLAUDE.md 생성 중...
✅ CLAUDE.md 생성 완료 (AGENTS.md 참조)

coding-style.md 생성 중...
✅ .claude/rules/coding-style.md 생성 완료

.gitignore 업데이트 중...
✅ .claude/plans/ 추가 완료

프로젝트 초기화 완료! 🎉
```

---

## 참고 사항

### 응답 언어
- 모든 응답은 **한국어**로 작성
- Git 커밋 메시지도 **한국어**로 작성

### 프로젝트 분석
- **explore 에이전트** 사용 권장 (빠르고 효율적)
- 프로젝트 크기가 큰 경우 주요 파일만 분석

### 기존 파일 보호
- 기존 파일이 있으면 **덮어쓰지 않고** 사용자에게 확인 요청
- 백업 옵션 제공 고려

### 확장성
- `.claude/commands/` 에 프로젝트 전용 명령어 추가 가능
- `.claude/agents/` 에 커스텀 에이전트 정의 가능
- `.claude/skills/` 에 워크플로우 정의 가능
