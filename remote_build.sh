#!/usr/bin/env bash
#
# remote_build.sh - 利用 cue-worker (8核24GB) 远程高速构建 Release APK
#
set -euo pipefail

REMOTE_HOST="root@100.85.82.59"
REMOTE_DIR="/root/build/meme-radar-android"
LOCAL_DIR="/home/deck/projects/meme-radar-android"

echo "=== 1. 同步源码到 cue-worker ==="
ssh "$REMOTE_HOST" "mkdir -p $REMOTE_DIR"
rsync -az --delete \
    --exclude "build/" \
    --exclude ".dart_tool/" \
    --exclude ".git/" \
    --exclude "*.apk" \
    "$LOCAL_DIR/" "$REMOTE_HOST:$REMOTE_DIR/"

echo "=== 2. 在 cue-worker 上执行高速 Release 构建 ==="
ssh "$REMOTE_HOST" "
set -euo pipefail
export ANDROID_HOME=/root/android-test/android-sdk
export ANDROID_SDK_ROOT=/root/android-test/android-sdk
export PATH=/opt/flutter/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH

cd $REMOTE_DIR
flutter pub get
flutter build apk --release
"

echo "=== 3. 将构建好的 APK 产物拉回本地 ==="
mkdir -p "$LOCAL_DIR/build/app/outputs/flutter-apk"
scp "$REMOTE_HOST:$REMOTE_DIR/build/app/outputs/flutter-apk/app-release.apk" \
    "$LOCAL_DIR/build/app/outputs/flutter-apk/app-release.apk"

echo "=== 4. 构建验证 ==="
APK="$LOCAL_DIR/build/app/outputs/flutter-apk/app-release.apk"
ls -lh "$APK"
sha256sum "$APK"
echo ">>> 远程编译成功完成！产物已就绪: $APK <<<"
