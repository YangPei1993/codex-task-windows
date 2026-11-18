#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
product="TaskWindows"
bundle_id="local.codex-task-windows"
bundle="$root/dist/Codex 会话窗口.app"
contents="$bundle/Contents"
binary="$contents/MacOS/$product"
archive="$root/dist/Codex 会话窗口-macOS.zip"

case "$mode" in
  run | --build-only | --package | --verify | --verify-data | --debug | --logs | --telemetry) ;;
  *)
    echo "用法：$0 [--build-only|--package|--verify|--verify-data [项目名]|--debug|--logs|--telemetry]" >&2
    exit 2
    ;;
esac

cd "$root"
mkdir -p "$root/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$root/.build/module-cache"
swift_options=(--cache-path "$root/.build/cache" --config-path "$root/.build/config" --security-path "$root/.build/security")
if [[ "${TASK_WINDOWS_SWIFTPM_COMPAT:-0}" == 1 ]]; then
  # 已受外层沙箱约束的构建环境可能不允许 SwiftPM 再嵌套一层 manifest 沙箱。
  swift_options+=(--disable-sandbox)
fi
if [[ "$mode" == --package ]]; then
  swift_options+=(--arch arm64 --arch x86_64)
fi
swift build "${swift_options[@]}"
built_binary="$(swift build "${swift_options[@]}" --show-bin-path)/$product"
if [[ "$mode" == --verify-data ]]; then
  shift
  exec "$built_binary" --verify-data "$@"
fi

if [[ "$mode" == --package ]]; then
  /usr/bin/lipo -verify_arch arm64 "$built_binary"
  /usr/bin/lipo -verify_arch x86_64 "$built_binary"
elif [[ "$mode" != --build-only ]]; then
  pkill -x "$product" >/dev/null 2>&1 || true
fi
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$built_binary" "$binary.new"
mv -f "$binary.new" "$binary"
cp Assets/AppIcon.icns "$contents/Resources/AppIcon.icns"
cp LICENSE "$contents/Resources/LICENSE"
cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$product</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>Codex 会话窗口</string>
  <key>CFBundleDisplayName</key><string>Codex 会话窗口</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.1</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
/usr/bin/codesign --force --sign - "$bundle"

case "$mode" in
  --build-only) printf '%s\n' "$bundle" ;;
  --package)
    staging="$(mktemp -d "$root/dist/.package.XXXXXX")"
    trap 'rm -f "$staging/app.zip"; rmdir "$staging"' EXIT
    /usr/bin/ditto -c -k --norsrc --keepParent "$bundle" "$staging/app.zip"
    mv -f "$staging/app.zip" "$archive"
    printf '%s\n' "$archive"
    ;;
  --debug) exec lldb -- "$binary" ;;
  --logs)
    /usr/bin/open -n "$bundle"
    exec /usr/bin/log stream --style compact --predicate "process == \"$product\""
    ;;
  --telemetry)
    /usr/bin/open -n "$bundle"
    exec /usr/bin/log stream --style compact --predicate "subsystem == \"$bundle_id\""
    ;;
  --verify)
    /usr/bin/open -n "$bundle"
    for attempt in 1 2 3 4 5; do
      if pgrep -x "$product" >/dev/null 2>&1; then exit 0; fi
      sleep 1
    done
    exit 1
    ;;
  run) /usr/bin/open -n "$bundle" ;;
esac
