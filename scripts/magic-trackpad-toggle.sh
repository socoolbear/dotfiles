#!/bin/zsh

# Alfred/launchd 등 PATH 가 최소한인 환경에서도 동작하도록 경로 고정
export BLUEUTIL=/opt/homebrew/bin/blueutil

# 해제(unpair)한 트랙패드는 페어링 목록에서 사라지므로, 한 번 찾은 주소는 여기에 남겨 둔다
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/magic-trackpad"
KNOWN_FILE="${STATE_DIR}/devices"

# 페어링 목록에서 Magic Trackpad 주소를 찾는다 (blueutil 형식: 소문자 + 하이픈)
findPairedTrackpads() {
  /usr/sbin/system_profiler SPBluetoothDataType 2>/dev/null \
    | awk '/Address:/ { addr = $2 } /Minor Type: Magic Trackpad/ { print addr }' \
    | tr 'A-F:' 'a-f-'
}

mkdir -p "${STATE_DIR}"
touch "${KNOWN_FILE}"

trackpads=(${(uf)"$(findPairedTrackpads; cat "${KNOWN_FILE}")"})
print -l ${trackpads} > "${KNOWN_FILE}"

if (( ${#trackpads} == 0 )); then
  echo "Magic Trackpad 를 찾지 못함 — 시스템 설정 > Bluetooth 에서 한 번 수동으로 페어링한 뒤 다시 실행"
  exit 0
fi

# 연결된 트랙패드가 있으면 해제
for device in ${trackpads}; do
  if [[ "$(${BLUEUTIL} --is-connected ${device})" = '1' ]]; then
    ${BLUEUTIL} --unpair ${device}
    echo "Magic Trackpad 연결 해제됨"
    exit 0
  fi
done

# 없으면 알려진 트랙패드에 차례로 연결한다
for device in ${trackpads}; do
  # 페어링이 남아 있으면 그대로 연결부터 시도한다. 먼저 해제하면 트랙패드가 검색 가능 상태가
  # 아닐 때 다시 페어링할 방법이 없어져, 케이블로만 복구된다
  if ${BLUEUTIL} --info ${device} | grep -q ", paired,"; then
    ${BLUEUTIL} --connect ${device}

    if [[ "$(${BLUEUTIL} --is-connected ${device})" = '1' ]]; then
      echo "Magic Trackpad 연결됨"
      exit 0
    fi
  fi

  ${BLUEUTIL} --unpair ${device}
  sleep 1
  ${BLUEUTIL} --pair ${device}

  # 페어링 직후 바로 연결하면 실패하므로 몇 초 간격으로 다시 시도한다.
  # pair/connect 는 실패해도 조용히 넘어가므로 결과를 다시 확인한다
  for attempt in 1 2 3; do
    sleep 3
    ${BLUEUTIL} --connect ${device}

    if [[ "$(${BLUEUTIL} --is-connected ${device})" = '1' ]]; then
      echo "Magic Trackpad 페어링 완료"
      exit 0
    fi
  done
done

echo "Magic Trackpad 연결 실패 — 다른 Mac 에 연결돼 있으면 그쪽에서 먼저 해제하거나, 트랙패드 전원을 껐다 켠 뒤 다시 실행"
exit 0  # Alfred 알림에 실패 문구가 뜨도록 0 으로 끝낸다
