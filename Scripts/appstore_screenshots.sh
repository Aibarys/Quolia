#!/bin/zsh
# Captures the App Store screenshot set on one simulator, in English and Russian.
# Usage: Scripts/appstore_screenshots.sh <simulator-udid> <out-dir>
# Needs a DEBUG build of Quolia in build/DerivedData (xcodebuild ... -derivedDataPath build/DerivedData).
set -e
U=$1; OUT=$2
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/Quolia.app
BOOK_RU="$PWD/Scripts/AppStoreFixtures/Тихие главы.fb2"

xcrun simctl boot $U 2>/dev/null || true
xcrun simctl ui $U appearance light
xcrun simctl status_bar $U override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

for LOC in en ru; do
  # A fresh install, so -seedDemoData fills the library from scratch.
  xcrun simctl uninstall $U com.quolia.reader 2>/dev/null || true
  xcrun simctl install $U $APP
  mkdir -p $OUT/$LOC
  if [ $LOC = ru ]; then LANGARGS=(-AppleLanguages "(ru)" -AppleLocale ru_RU); BOOK="Тихие главы"
  else LANGARGS=(-AppleLanguages "(en)" -AppleLocale en_US); BOOK="On Reading Slowly"; fi
  shoot() { # name delay args...
    local name=$1 delay=$2; shift 2
    xcrun simctl terminate $U com.quolia.reader >/dev/null 2>&1 || true
    xcrun simctl launch $U com.quolia.reader -completeOnboarding -seedDemoData "${LANGARGS[@]}" "$@" >/dev/null
    sleep $delay
    xcrun simctl io $U screenshot $OUT/$LOC/$name.png >/dev/null 2>&1 && echo "$OUT/$LOC/$name.png"
  }
  if [ $LOC = ru ]; then
    shoot 1-library 20 -tab library -importFile "$BOOK_RU"
    shoot 2-reader 14 -openTitle "$BOOK" -openChapter 0 -readerLayout paged -theme sepia -focus off
    shoot 3-quote 14 -openTitle "$BOOK" -readerLayout paged -theme sepia -focus off -readerSheet quote -quoteText "Читать — значит возвращаться."
    shoot 4-focus 14 -openTitle "$BOOK" -openChapter 0 -readerLayout scroll -focus line -theme dark -readerSheet chromeHidden
    shoot 5-settings 14 -openTitle "$BOOK" -readerLayout paged -theme light -focus off -readerSheet settings
    shoot 6-remember 12 -tab remember
  else
    shoot 1-library 22 -tab library
    shoot 2-reader 14 -openTitle "$BOOK" -readerLayout paged -theme sepia -focus off
    shoot 3-quote 14 -openTitle "$BOOK" -readerLayout paged -theme sepia -focus off -readerSheet quote
    shoot 4-focus 14 -openTitle "$BOOK" -readerLayout scroll -focus line -theme dark -readerSheet chromeHidden
    shoot 5-notes 12 -tab notes
    shoot 6-remember 12 -tab remember
  fi
done
