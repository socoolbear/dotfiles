---
name: worktree-refresh
description: git worktree(또는 일반 로컬 브랜치)를 최신 기본 브랜치(main)에 맞춘다. 저장소 상태를 판정해 두 갈래로 처리한다 — PR 이 병합돼 브랜치에 고유 커밋이 없으면 최신 main 지점에서 재생성(reset)하고, 작업이 남은 진행 중 브랜치면 main 을 브랜치로 병합(merge)해 동기화한다. "main 최신화하고 병합해줘", "브랜치가 병합되면서 삭제됐어", "worktree 브랜치 재생성", "PR 머지됐으니 브랜치 리셋", "머지 후 다음 작업 시작 준비", "브랜치에 main 반영해줘", "최신 main 받아와" 같은 요청이면 반드시 이 스킬을 사용할 것.
---

# worktree-refresh — worktree 브랜치를 최신 기본 브랜치에 맞추기

장수 브랜치(예: msa 의 `feat/domain-post`)는 "기능 묶음 → PR → 병합(원격 브랜치 삭제) → 같은 이름으로 다시 시작" 을 반복하고, 그 사이사이 진행 중인 브랜치에 최신 main 을 당겨오는 일이 섞인다.

**이 두 요청은 말이 비슷한데 동작이 정반대다** — 앞은 브랜치를 버리고(reset), 뒤는 브랜치를 살린 채 main 을 얹는다(merge). 그래서 경로는 **사용자 표현이 아니라 저장소 상태로 판정한다.**

worktree 를 지웠다 다시 만들지 않는 것은 두 경로 공통 원칙이다 —
- worktree 가 물고 있는 브랜치는 git 이 삭제를 거부한다.
- worktree 를 재생성하면 gitignore 된 로컬 파일(`.env`, 로컬 인프라 설정 등)이 날아간다. `reset --hard`·`merge` 는 추적 파일만 건드리므로 로컬 개발 환경이 그대로 보존된다.

## 절차

### 0. 대상 파악
- worktree 디렉토리(보통 현재 cwd)에서 `git branch --show-current` 로 브랜치 이름을 확인한다. 사용자가 브랜치를 지정하면 그것을 쓴다.
- 기본 브랜치는 `origin/HEAD` 기준으로 파악한다 (모르면 `git remote show origin | grep 'HEAD branch'`; msa 는 `main`).
- 레포 루트(메인 체크아웃)는 `git worktree list` 의 첫 줄이다.
- **대상 브랜치가 기본 브랜치 자신이면 즉시 중단한다.** main 은 항상 "고유 커밋 없음" 이라 A 로 판정되는데, A 의 push 가 곧 main 직접 푸시가 된다. 이 스킬은 기능 브랜치 전용이다.

### 1. 상태 판정 — 경로를 여기서 정한다

```bash
git fetch origin --prune                       # 기본 브랜치·대상 브랜치 최신화 + 삭제된 원격 브랜치 정리
git status --short                             # 추적 파일 변경(M/A/D/R)이 없어야 한다 (두 경로 공통 차단 조건)
git merge-base --is-ancestor HEAD origin/<기본브랜치> && echo 포함됨
git ls-remote --heads origin <브랜치>          # 원격 브랜치 생존 여부
```

| HEAD 가 origin/기본브랜치에 | 원격 브랜치 | 뜻 | 경로 |
|---|---|---|---|
| 포함됨 | (무관) | 브랜치 고유 커밋 없음 = 병합 완료 | **A. 리셋** |
| 미포함 | 살아 있음 | 작업이 남은 진행 중 브랜치 | **B. 동기화** |
| 미포함 | 없음 | squash 병합됐거나 미푸시 커밋 | **C. 멈춤** |

추적 파일 변경은 **두 경로 공통 차단 조건**이다 — reset 은 지워버리고, merge 는 충돌 시 상태가 꼬인다. 걸리면 멈추고 `git status` 를 사용자에게 보여준다. 미추적(`??`) 파일은 어느 경로도 손대지 않으므로 있어도 된다 (`.env` 등 — 이 워크플로우에선 있는 게 정상).

### 2. 실행 전 한 줄 보고 — 건너뛰지 말 것
경로를 정했으면 **무엇을 할지 먼저 알린다.** ("A: 고유 커밋이 없어 브랜치를 origin/main 지점으로 리셋합니다" / "B: origin/main 을 브랜치에 병합합니다.") 두 경로의 결과가 정반대라, 사용자가 반대쪽을 기대했다면 여기서 바로잡아야 한다.

### 3. 메인 체크아웃의 기본 브랜치 최신화 (두 경로 공통)
```bash
git -C <레포루트> branch --show-current        # 기본 브랜치일 때만 pull
git -C <레포루트> pull --ff-only origin <기본브랜치>
```
메인 체크아웃이 다른 브랜치를 물고 있으면 pull 하지 말고 그 사실만 보고한다 (남의 작업 공간을 바꾸지 않는다).

### A. 리셋 경로 — 병합이 끝난 브랜치를 다시 세운다
worktree 디렉토리 안에서:
```bash
git reset --hard origin/<기본브랜치>
git push -u origin <브랜치>       # 병합으로 삭제된 원격 브랜치를 새로 만들고 트래킹을 잇는다
```
원격 브랜치가 살아 있는 채로 이 경로에 왔다면 push 는 fast-forward 로 통과한다. **거부되면 판정이 틀린 것이니 멈추고 다시 본다 — force 로 밀지 않는다.**

### B. 동기화 경로 — 진행 중 브랜치에 최신 main 을 얹는다
먼저 원격 브랜치와 갈라졌는지 본다:
```bash
git merge-base --is-ancestor origin/<브랜치> HEAD && echo "로컬이 앞섬 — 그대로 진행"
git merge-base --is-ancestor HEAD origin/<브랜치> && echo "로컬이 뒤처짐 — pull --ff-only 먼저"
# 둘 다 아니면 갈라진 것이다 → 멈춘다 (다른 작업 공간에서 push 했을 수 있다)
```
그다음 병합하고 올린다:
```bash
git merge origin/<기본브랜치>
git push origin <브랜치>
```
- **rebase 가 아니라 merge 다.** 이미 push 된 브랜치를 rebase 하면 force push 가 필요해 협업 중 사고가 난다.
- **충돌이 나면 자동 해결을 시도하지 않는다.** `git diff --name-only --diff-filter=U` 로 충돌 파일을 보여주고, 직접 해결할지 `git merge --abort` 로 되돌릴지 사용자가 정한다.
- push 에 force 는 필요 없다. 거부되면 위 갈라짐 검사를 놓친 것이다.

### C. 멈춤 — 판정이 모호할 때
`gh pr list --head <브랜치> --state merged` 로 squash 병합 여부를, `git log --oneline origin/<기본브랜치>..HEAD` 로 사라질 커밋 목록을 확인해 사용자에게 보여준다.
- squash 병합이 확인되면 → A 로 진행해도 되는지 **명시적 확인을 받고서만** 움직인다.
- 미푸시 작업이면 → 먼저 push 할지 B 로 갈지 사용자가 정한다.

### 4. 결과 보고
- `git worktree list` 로 worktree 등재가 유지됐는지, 브랜치 지점이 의도대로인지 확인해 보고한다.
- **어느 경로로 갔는지** 와 gitignore 된 로컬 파일이 보존됐음을 함께 언급한다 (사용자가 로컬 환경 유실을 걱정하는 지점이다).

## 주의
- `reset --hard` 는 미커밋 **추적 파일** 변경을 지운다 — 1단계 clean 검사를 건너뛰지 말 것.
- 기본 브랜치에는 pull 만 한다. 직접 푸시하지 않는다 (msa 는 main 직접 푸시 금지 규칙이 있다).
- **"병합해줘" 라는 말만으로 경로를 고르지 않는다.** 실제로 병합이 끝난 브랜치에 "main 최신화하고 병합해줘" 요청이 온 적이 있고, 그때 옳은 동작은 merge 가 아니라 A(리셋)였다. 말과 상태가 어긋날 때 2단계 사전 보고가 그걸 잡는다.
- force push 는 어느 경로에서도 쓰지 않는다. 필요해 보이면 판정이 틀렸다는 신호다.
