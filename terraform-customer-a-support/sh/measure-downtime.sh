#!/usr/bin/env bash
# 단절 시간 측정 — Phase 3 전환을 시작하기 전에 별도 터미널에서 먼저 띄운다
#
# 사용법:  ./sh/measure-downtime.sh
# 중지:    Ctrl+C
# 결과:    results/downtime.log

source "$(dirname "$0")/_common.sh"
LOG="$RESULT_DIR/downtime.log"
URL="https://sms.$DOMAIN/"

echo "측정 시작: $URL"
echo "로그: $LOG"
echo "Ctrl+C 로 중지. 전환 작업이 끝나고 응답이 안정된 뒤에 멈춘다"
echo

: > "$LOG"
while true; do
  T=$(date '+%H:%M:%S')
  # --max-time 2 로 잡아야 1초 간격이 밀리지 않는다.
  # 실패 시 curl 은 000 을 출력한다
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$URL" 2>/dev/null)
  if [ "$CODE" = "200" ]; then
    printf '%s %s\n' "$T" "$CODE" | tee -a "$LOG"
  else
    printf '%s %s FAIL\n' "$T" "${CODE:-000}" | tee -a "$LOG"
  fi
  sleep 1
done
