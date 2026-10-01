#!/usr/bin/env bash
#
# 把插件源码编译成单文件 plugin.dex。
#
#   用法:  ./build_dex.sh [--push]
#          --push  编译成功后 adb push 到 /sdcard/plugin.dex
#
#   可覆盖的环境变量:
#          ANDROID_HOME / ANDROID_SDK_ROOT   Android SDK 根目录
#          ANDROID_JAR                       指定 android.jar
#          PLUGIN_CLASSPATH                  编译期 classpath（冒号分隔的多个 jar），优先级最高
#          FRAGMENT_JAR                      只指定 androidx.fragment 的 classes.jar（不推荐，
#                                            缺传递依赖会编译失败；一般用 PLUGIN_CLASSPATH）
#
# 依赖: javac、d8（Android SDK build-tools 自带）、unzip。
#
# 说明: 插件 dex 里不打包 androidx —— androidx.fragment.Fragment 等由宿主的 ClassLoader 提供，
#       两边必须是同一个类才能塞进宿主的 FragmentManager（见 ProxyActivity 注释）。
#       所以这里的 androidx jar 只用于「编译期」，不会被 d8 打进 dex。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$HERE/plugin"
OUT_DIR="$HERE/out"
CLASSES_DIR="$OUT_DIR/classes"
LIBS_DIR="$OUT_DIR/libs"
DEX_OUT="$OUT_DIR/plugin.dex"

PUSH=0
[ "${1:-}" = "--push" ] && PUSH=1

log() { echo "[build_dex] $*"; }
die() { echo "[build_dex] 错误: $*" >&2; exit 1; }

# ---------- 1. 定位 Android SDK ----------
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK" ]; then
  for p in "$HOME/Android/Sdk" /usr/local/lib/android/sdk /root/android/sdk /opt/android-sdk; do
    [ -d "$p" ] && SDK="$p" && break
  done
fi
[ -n "$SDK" ] || die "找不到 Android SDK，请设置 ANDROID_HOME"

# ---------- 2. 定位 android.jar（取最高版本） ----------
if [ -z "${ANDROID_JAR:-}" ]; then
  ANDROID_JAR="$(ls -1 "$SDK"/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -1 || true)"
fi
[ -f "${ANDROID_JAR:-}" ] || die "找不到 android.jar（$SDK/platforms 下），或用 ANDROID_JAR 指定"
log "android.jar: $ANDROID_JAR"

# ---------- 3. 定位 d8（取最高 build-tools） ----------
D8="$(ls -1 "$SDK"/build-tools/*/d8 2>/dev/null | sort -V | tail -1 || true)"
[ -x "${D8:-}" ] || die "找不到 d8（$SDK/build-tools/*/d8）"
log "d8: $D8"

# ---------- 4. 组装编译期 classpath ----------
if [ -n "${PLUGIN_CLASSPATH:-}" ]; then
  CP="$PLUGIN_CLASSPATH"
elif [ -n "${FRAGMENT_JAR:-}" ]; then
  CP="$FRAGMENT_JAR"
else
  # 从 Gradle 缓存自动收集所有 androidx 的类（宿主工程构建过一次，缓存里就有）。
  # 注意两点：
  #   1) 有的库是 aar（类在其中的 classes.jar 里），有的是普通 jar（如 lifecycle-common）；
  #   2) KMP 库的某个 artifact 最新版本可能只有元数据、没有 classes（如 lifecycle-common 2.10.0），
  #      要按版本从高到低找第一个「真正带类」的文件。
  CACHE="$HOME/.gradle/caches/modules-2/files-2.1"
  rm -rf "$LIBS_DIR"
  mkdir -p "$LIBS_DIR"

  collect_artifact() {
    local art_dir="$1" name out f
    name="$(basename "$art_dir")"
    out="$LIBS_DIR/$name.jar"
    # 优先 aar：按版本从高到低找第一个能解出非空 classes.jar 的
    for f in $(find "$art_dir" -name '*.aar' 2>/dev/null | sort -Vr); do
      if unzip -p "$f" classes.jar > "$out" 2>/dev/null && [ -s "$out" ]; then
        return 0
      fi
    done
    rm -f "$out"
    # 再退到普通 jar（排除 sources/javadoc）
    for f in $(find "$art_dir" -name '*.jar' \
                  ! -name '*-sources.jar' ! -name '*-javadoc.jar' 2>/dev/null | sort -Vr); do
      if cp "$f" "$out" 2>/dev/null && [ -s "$out" ]; then
        return 0
      fi
    done
    rm -f "$out"
    return 1
  }

  n=0
  for group_dir in "$CACHE"/androidx.*; do
    [ -d "$group_dir" ] || continue
    for art_dir in "$group_dir"/*; do
      [ -d "$art_dir" ] || continue
      if collect_artifact "$art_dir"; then
        n=$((n + 1))
      fi
    done
  done
  [ "$n" -gt 0 ] || die "Gradle 缓存里没找到 androidx；请用 PLUGIN_CLASSPATH 手动指定编译期 jar"
  log "从 Gradle 缓存收集了 $n 个 androidx jar"
  CP="$(ls "$LIBS_DIR"/*.jar | tr '\n' ':')"
fi
log "编译期 classpath 就绪"

# ---------- 5. 编译 ----------
rm -rf "$CLASSES_DIR"
mkdir -p "$CLASSES_DIR"

# -source/-target 8 → 产出 class 版本 52，兼容所有 d8；bootclasspath 指向 android.jar。
# shellcheck disable=SC2046
javac -source 8 -target 8 \
      -bootclasspath "$ANDROID_JAR" \
      -classpath "$CP" \
      -d "$CLASSES_DIR" \
      $(find "$SRC_DIR" -name '*.java') \
      -Xlint:-options

log "javac 完成，生成 class 文件："
find "$CLASSES_DIR" -name '*.class' | sed "s|$CLASSES_DIR/|    |"

# ---------- 6. 转 dex ----------
# 只把插件自己的 class 交给 d8，不掺入 androidx。
# shellcheck disable=SC2046
"$D8" --lib "$ANDROID_JAR" --min-api 24 --output "$OUT_DIR" \
      $(find "$CLASSES_DIR" -name '*.class')
mv "$OUT_DIR/classes.dex" "$DEX_OUT"

log "生成: $DEX_OUT ($(wc -c < "$DEX_OUT") 字节)"

# ---------- 7. 可选推送 ----------
if [ "$PUSH" = "1" ]; then
  command -v adb >/dev/null 2>&1 || die "未找到 adb，无法推送"
  adb push "$DEX_OUT" /sdcard/plugin.dex
  log "已推送到 /sdcard/plugin.dex"
fi
