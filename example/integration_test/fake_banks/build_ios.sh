#!/bin/bash
# Собирает «банк» для интеграционных тестов на iOS Simulator без Xcode-проекта.
#
#   example/integration_test/fake_banks/build_ios.sh <out_dir>
#
# FakeBank.app (ru.smena.fakebank) открывает bank100000000111:// (есть в Info.plist примера)
# и bank100000000153:// (нет в Info.plist - проверка лимита 50 схем).
set -euo pipefail

OUT=${1:?usage: build_ios.sh <out_dir>}
APP="$OUT/FakeBank.app"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
rm -rf "$APP" && mkdir -p "$APP"

cat > "$WORK/main.swift" <<'EOF'
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let controller = UIViewController()
    controller.view.backgroundColor = .systemYellow
    let label = UILabel()
    label.text = "FAKE BANK OPENED"
    label.frame = CGRect(x: 20, y: 200, width: 300, height: 40)
    controller.view.addSubview(label)
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = controller
    window?.makeKeyAndVisible()
    return true
  }

  // сразу возвращаемся в пример, чтобы iOS не приостановил интеграционный тест
  func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      if let back = URL(string: "sbpexample://back") { app.open(back) }
    }
    return true
  }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
EOF

xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios15.0-simulator -O \
  -o "$APP/FakeBank" "$WORK/main.swift"

cat > "$APP/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>ru.smena.fakebank</string>
  <key>CFBundleName</key><string>FakeBank</string>
  <key>CFBundleExecutable</key><string>FakeBank</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>15.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array><string>bank100000000111</string><string>bank100000000153</string></array>
    </dict>
  </array>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1
echo "$APP"
