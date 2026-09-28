#!/usr/bin/env bash
# 重新生成 Flutter 模块的 AAR（本地 Maven 仓库）。
# 产物目录：flutter_bridge/build/host/outputs/repo
# 之后 app 模块通过 settings.gradle.kts 里声明的该目录作为 maven 仓库依赖 flutter_debug/flutter_release。
set -euo pipefail

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-arm64}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
if ! command -v flutter >/dev/null 2>&1; then
  export PATH="$PATH:/root/.local/flutter-3.47.2/bin"
fi

cd "$(dirname "$0")/flutter_bridge"

# debug：JIT，任何主机都能出（arm64 容器本地可用）。
# Flutter 默认会构建 release/debug/profile，而 profile/release 需要 AOT gen_snapshot（仅 x86_64 主机），
# 所以这里显式关掉它们。
flutter build aar --debug --no-profile --no-release --target-platform android-arm64

# 若要出 release AAR，请在 x86_64 主机 / GitHub Actions 上执行：
#   flutter build aar --release --no-debug --no-profile --target-platform android-arm64
