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
echo "Magic Trackpad 페어링 완료"
