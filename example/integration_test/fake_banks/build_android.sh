#!/bin/bash
# Собирает APK «банков» для интеграционных тестов: только манифест, без кода.
# Activity - android.app.Activity из фреймворка, поэтому dex не нужен.
#
#   example/integration_test/fake_banks/build_android.sh <out_dir>
#
# fake_scheme_bank.apk  ru.smena.fakebank   - открывает bank100000000111:// и bank100000000153:// (qr.nspk.ru)
# fake_https_bank.apk   ru.rshb.ownfinance  - открывает только https://qr.nspk.ru (как новое приложение РСХБ)
set -euo pipefail

OUT=${1:?usage: build_android.sh <out_dir>}
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
BUILD_TOOLS=$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)
PLATFORM=$(ls -d "$SDK"/platforms/android-* | sort -V | tail -1)
mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

KEYSTORE="$OUT/fake_banks.keystore"
if [ ! -f "$KEYSTORE" ]; then
  keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android -alias fake \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=fake bank" >/dev/null 2>&1
fi

build() {
  local name=$1 package=$2 filters=$3
  cat > "$WORK/AndroidManifest.xml" <<EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$package"
    android:versionCode="1" android:versionName="1.0">
  <uses-sdk android:minSdkVersion="21" android:targetSdkVersion="35"/>
  <application android:label="$name" android:hasCode="false">
    <activity android:name="android.app.Activity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
      $filters
    </activity>
  </application>
</manifest>
EOF
  "$BUILD_TOOLS/aapt2" link -o "$WORK/$name.unsigned.apk" -I "$PLATFORM/android.jar" --manifest "$WORK/AndroidManifest.xml"
  "$BUILD_TOOLS/zipalign" -f 4 "$WORK/$name.unsigned.apk" "$WORK/$name.aligned.apk"
  "$BUILD_TOOLS/apksigner" sign --ks "$KEYSTORE" --ks-pass pass:android --out "$OUT/$name.apk" "$WORK/$name.aligned.apk"
  echo "$OUT/$name.apk"
}

view_filter() {
  echo "<intent-filter><action android:name=\"android.intent.action.VIEW\"/><category android:name=\"android.intent.category.DEFAULT\"/><category android:name=\"android.intent.category.BROWSABLE\"/><data android:scheme=\"$1\" android:host=\"qr.nspk.ru\"/></intent-filter>"
}

build fake_scheme_bank ru.smena.fakebank "$(view_filter bank100000000111) $(view_filter bank100000000153)"
build fake_https_bank ru.rshb.ownfinance "$(view_filter https)"
