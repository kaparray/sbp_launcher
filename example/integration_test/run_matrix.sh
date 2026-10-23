#!/bin/bash
# Прогон интеграционных тестов на матрице эмуляторов Android и симуляторов iOS.
# Каждое устройство создаётся с нуля и удаляется после прогона.
#
#   example/integration_test/run_matrix.sh android 21 22 ... 36
#   example/integration_test/run_matrix.sh ios com.apple.CoreSimulator.SimRuntime.iOS-17-2 ...
#
# EMULATOR_GPU=host - аппаратный GPU (нужен для API 30: со swiftshader Flutter зависает на старте).
# Нужны: flutter в PATH, Android SDK (system-images;android-N;default;arm64-v8a), Xcode.
# Результаты: $OUT (по умолчанию build/sbp_matrix): <device>.log и summary.txt
set -uo pipefail

PLATFORM=${1:?usage: run_matrix.sh android|ios <versions...>}
shift
EXAMPLE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$EXAMPLE/build/sbp_matrix}
FAKES=$OUT/fake_banks
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
mkdir -p "$OUT"

record() { echo "$1 $2" | tee -a "$OUT/summary.txt"; }

run_tests() { # <device id> <log>
  (cd "$EXAMPLE" && flutter test integration_test -d "$1" --reporter expanded --no-pub) >"$2" 2>&1
}

if [ "$PLATFORM" = android ]; then
  "$EXAMPLE/integration_test/fake_banks/build_android.sh" "$FAKES" >/dev/null || { echo "fake banks build failed" >&2; exit 1; }
  ADB=$SDK/platform-tools/adb
  for API in "$@"; do
    NAME=sbp_api$API
    PORT=5580
    SERIAL=emulator-$PORT
    echo "== Android API $API"
    echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" -s create avd -f -n "$NAME" \
      -k "system-images;android-$API;default;arm64-v8a" -d pixel_5 >/dev/null 2>&1 || {
      record "android-$API" "SKIP(no image)"; continue; }
    "$SDK/emulator/emulator" -avd "$NAME" -port $PORT -no-window -no-audio -no-boot-anim -no-snapshot \
      -gpu "${EMULATOR_GPU:-swiftshader_indirect}" >"$OUT/$NAME.emulator.log" 2>&1 &
    BOOTED=0
    for _ in $(seq 300); do # до 10 минут: старые образы грузятся долго
      if [ "$("$ADB" -s $SERIAL shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
        BOOTED=1
        break
      fi
      sleep 2
    done
    if [ $BOOTED = 0 ]; then
      record "android-$API" "SKIP(boot timeout)"
    else
      sleep 5
      for APK in fake_scheme_bank fake_https_bank; do
        "$ADB" -s $SERIAL install -r "$FAKES/$APK.apk" >>"$OUT/$NAME.install.log" 2>&1 || echo "install $APK failed" >&2
      done
      if run_tests $SERIAL "$OUT/$NAME.log"; then record "android-$API" PASS; else record "android-$API" FAIL; fi
    fi
    "$ADB" -s $SERIAL emu kill >/dev/null 2>&1
    sleep 5
    "$SDK/cmdline-tools/latest/bin/avdmanager" -s delete avd -n "$NAME" >/dev/null 2>&1
  done
elif [ "$PLATFORM" = ios ]; then
  "$EXAMPLE/integration_test/fake_banks/build_ios.sh" "$FAKES" >/dev/null || { echo "fake banks build failed" >&2; exit 1; }
  for RUNTIME in "$@"; do
    NAME=sbp_${RUNTIME##*.}
    echo "== $RUNTIME"
    UDID=$(xcrun simctl create "$NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation "$RUNTIME" 2>/dev/null) || {
      record "$RUNTIME" "SKIP(no runtime)"; continue; }
    xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" >/dev/null
    xcrun simctl install "$UDID" "$FAKES/FakeBank.app"
    if run_tests "$UDID" "$OUT/$NAME.log"; then record "$RUNTIME" PASS; else record "$RUNTIME" FAIL; fi
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1
    xcrun simctl delete "$UDID"
  done
fi
