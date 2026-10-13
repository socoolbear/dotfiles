#!/bin/zsh

# Alfred/launchd 등 PATH 가 최소한인 환경에서도 동작하도록 경로 고정
export BLUEUTIL=/opt/homebrew/bin/blueutil
export DEVICE_ID=b4-fa-48-dd-b0-91

res=$($BLUEUTIL --is-connected $DEVICE_ID)

if [[ "$res" = '1' ]]; then
  $BLUEUTIL --unpair $DEVICE_ID
  echo "Magic Trackpad 연결 해제됨"
  exit 0
fi

$BLUEUTIL --unpair $DEVICE_ID
sleep 1
$BLUEUTIL --pair $DEVICE_ID
sleep 1
$BLUEUTIL --connect $DEVICE_ID

# pair/connect 는 실패해도 조용히 넘어가므로 결과를 다시 확인한다
if [[ "$($BLUEUTIL --is-connected $DEVICE_ID)" != '1' ]]; then
  echo "Magic Trackpad 연결 실패 — 다른 Mac 에 연결돼 있으면 그쪽에서 먼저 해제하거나, 트랙패드 전원을 껐다 켠 뒤 다시 실행"
  exit 0  # Alfred 알림에 실패 문구가 뜨도록 0 으로 끝낸다
fi

echo "Magic Trackpad 페어링 완료"
