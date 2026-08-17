#!/bin/bash
#
# SwiftBar 플러그인 — 잠자기 방지 (pmset disablesleep) 토글.
# 파일명 규칙이 곧 설정이다: <이름>.<갱신주기>.<확장자> — 5s = 5 초마다 재실행.
#
# 상태 조회는 권한이 필요 없고, 변경만 root 다. 변경 로직과 자동 해제 타이머는
# ~/.local/bin/sleepguard (scripts/sleepguard-toggle.sh) 가 담당한다.

export PATH=/usr/bin:/bin:/usr/sbin

SLEEPGUARD="${HOME}/.local/bin/sleepguard"

if [ ! -x "${SLEEPGUARD}" ]; then
  echo ":exclamationmark.triangle: | sfcolor=red"
  echo "---"
  echo "sleepguard 미설치 — make sync && make sleepguard | color=red"
  exit 0
fi

# 만료된 예약이 있으면 여기서 해제된다 (5 초 폴링을 타이머로 재사용)
"${SLEEPGUARD}" tick

STATE=$(pmset -g | awk '/SleepDisabled/{print $2}')

if [ "${STATE}" = "1" ]; then
  echo ":cup.and.saucer.fill: | sfcolor=orange"
  echo "---"
  echo "잠자기 방지: ON ($(${SLEEPGUARD} remaining)) | color=green"
  echo "끄기 | shell=${SLEEPGUARD} param1=off terminal=false refresh=true"
else
  echo ":moon.zzz: | sfcolor=gray"
  echo "---"
  echo "잠자기 방지: OFF | color=gray"
  echo "1시간 켜기 | shell=${SLEEPGUARD} param1=on param2=60 terminal=false refresh=true"
  echo "4시간 켜기 | shell=${SLEEPGUARD} param1=on param2=240 terminal=false refresh=true"
  echo "무제한 켜기 | shell=${SLEEPGUARD} param1=on terminal=false refresh=true"
fi

echo "---"
echo "현재 상태 새로고침 | refresh=true"
