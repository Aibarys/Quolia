#!/bin/zsh
# Usage: Scripts/shot.sh <name> [delay] [launch args...]
UDID=${UDID:-D46B2F07-BB0D-4452-81D6-0A4B76772A36}
OUT=${SHOTS:-/tmp/quolia-shots}
mkdir -p $OUT
name=$1; delay=$2; shift 2
xcrun simctl terminate $UDID com.quolia.reader >/dev/null 2>&1
xcrun simctl launch $UDID com.quolia.reader "$@" >/dev/null
sleep $delay
xcrun simctl io $UDID screenshot $OUT/$name.png >/dev/null 2>&1 && echo "$OUT/$name.png"
