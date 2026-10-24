#!/bin/bash
source common.sh
set_keys
export VERSION=$(grep -m1 -o '[0-9]\+\(\.[0-9]\+\)\{3\}' vanadium/args.gn)
export CHROMIUM_SOURCE=https://chromium.googlesource.com/chromium/src.git # https://github.com/chromium/chromium.git
export DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói phụ thuộc cần thiết
sudo apt-get update
sudo apt-get install -y sudo lsb-release file nano git curl python3 python3-pillow imagemagick librsvg2-bin
sudo dpkg --add-architecture i386; sudo apt-get update; sudo apt-get install -y libgcc-s1:i386

# 2. Tải depot_tools của Chromium
git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$PWD/depot_tools:$PATH"

# 3. Tải và checkout mã nguồn Chromium theo phiên bản
mkdir -p chromium/src/out/Default; cd chromium/src
git init
git remote add origin $CHROMIUM_SOURCE
git fetch --depth 1 $CHROMIUM_SOURCE +refs/tags/$VERSION:chromium_$VERSION
git checkout $VERSION
cp $SCRIPT_DIR/.gclient ../.gclient

# 4. Lọc và áp dụng các patch Vanadium/Titanium
rm -rf $SCRIPT_DIR/vanadium/patches/*trichrome-{apk-build-targets,browser-apk-targets}.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*{detailed,supported}-language*.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*javascript-optimizer-{site-setting,settings-UI}.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*component-updates.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*{pdf,PDF,for-content-public,toolbar-button,configs-from-config-app,config-app-parsing,new-tab-card,predictive-back}*.patch
# rm -rf $SCRIPT_DIR/vanadium/patches/*crashpad*.patch

replace "$SCRIPT_DIR/vanadium/patches" "VANADIUM" "TITANIUM"
replace "$SCRIPT_DIR/vanadium/patches" "Vanadium" "Titanium"
replace "$SCRIPT_DIR/vanadium/patches" "vanadium" "titanium"
git am --whitespace=nowarn --keep-non-patch $SCRIPT_DIR/vanadium/patches/*.patch

# 5. Đồng bộ thư viện và cài đặt các phụ thuộc build
gclient sync -D --no-history --nohooks
gclient runhooks
./build/install-build-deps.sh --no-prompt

# 6. Chuẩn bị cấu hình build
source $SCRIPT_DIR/patch.sh
cp $SCRIPT_DIR/args.gn out/Default/args.gn

# --- Đảm bảo hỗ trợ tối thiểu cho Android 7.0 (API 24) ---
if ! grep -q "min_sdk_version" out/Default/args.gn; then
    echo 'min_sdk_version = 24' >> out/Default/args.gn
fi

# Sinh file build ban đầu (32-bit / arm)
gn gen out/Default
mkdir -p out/tmp out/release

# 7. Build bản 32-bit (armeabi-v7a) - Dành riêng cho thiết bị Android 7
autoninja -C out/Default chrome_public_apk
mv $(find out/Default/apks -name 'Chrome*.apk') out/tmp/$VERSION-armeabi-v7a.apk

# 8. Đổi cấu hình sang 64-bit (arm64-v8a) và sinh lại cấu hình GN
#sed -i 's/target_cpu = "arm"/target_cpu = "arm64"/' out/Default/args.gn
#gn gen out/Default

# Build bản 64-bit APK & AAB
#autoninja -C out/Default chrome_public_apk chrome_public_bundle
#mv $(find out/Default/apks -name 'Chrome*.apk') out/tmp/$VERSION-arm64-v8a.apk
#mv $(find out/Default/apks -name 'Chrome*.aab') out/tmp/$VERSION-arm64-v8a.aab

# 9. Ký file (Sign APK/AAB) bằng SDK/JDK nội bộ
export PATH=$PWD/third_party/jdk/current/bin/:$PATH
export ANDROID_HOME=$PWD/third_party/android_sdk/public

sign_apk out/tmp/$VERSION-armeabi-v7a.apk out/release/$VERSION-armeabi-v7a.apk
#sign_apk out/tmp/$VERSION-arm64-v8a.apk out/release/$VERSION-arm64-v8a.apk
#sign_aab out/tmp/$VERSION-arm64-v8a.aab out/release/$VERSION-arm64-v8a.aab

# 10. Dọn dẹp key tạm
rm -rf $SCRIPT_DIR/keys
