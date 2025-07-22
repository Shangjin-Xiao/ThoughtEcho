#!/bin/bash

# 32位Android设备兼容性验证脚本
# 该脚本验证应用构建配置是否支持32位设备

set -e

echo "=== ThoughtEcho 32位设备兼容性验证 ==="
echo ""

# 检查当前目录
if [[ ! -f "pubspec.yaml" ]]; then
    echo "错误: 请在项目根目录运行此脚本"
    exit 1
fi

echo "1. 检查ABI过滤器配置..."
if grep -q "abiFilters 'armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'" android/app/build.gradle; then
    echo "✅ ABI过滤器包含所有必需架构 (armeabi-v7a, arm64-v8a, x86, x86_64)"
else
    echo "❌ ABI过滤器配置缺失或不完整"
    exit 1
fi

echo ""
echo "2. 检查最低SDK版本..."
MIN_SDK=$(grep "minSdkVersion" android/app/build.gradle | grep -o '[0-9]\+')
if [[ $MIN_SDK -ge 21 ]]; then
    echo "✅ minSdkVersion = $MIN_SDK (满足 ≥21 要求)"
else
    echo "❌ minSdkVersion = $MIN_SDK (需要 ≥21)"
    exit 1
fi

echo ""
echo "3. 检查SafeMMKV兼容层..."
if grep -q "32位ARM设备优先使用SharedPreferences" lib/utils/mmkv_ffi_fix.dart; then
    echo "✅ SafeMMKV包含32位设备兼容处理"
else
    echo "❌ SafeMMKV兼容层配置缺失"
    exit 1
fi

echo ""
echo "4. 检查ThoughtEchoApplication 64位检测..."
if grep -q "is64BitDevice" android/app/src/main/java/com/shangjin/thoughtecho/ThoughtEchoApplication.java; then
    echo "✅ Java应用类包含64位设备检测逻辑"
else
    echo "❌ Java应用类缺少64位设备检测"
    exit 1
fi

echo ""
echo "5. 检查内存优化配置..."
if grep -q "largeHeap.*true" android/app/src/main/AndroidManifest.xml; then
    echo "✅ 应用清单配置了大堆内存"
else
    echo "⚠️  应用清单未配置大堆内存（可选）"
fi

echo ""
echo "6. 检查MMKV ProGuard规则..."
if grep -q "com.tencent.mmkv" android/app/proguard-rules.pro; then
    echo "✅ ProGuard规则保护MMKV类"
else
    echo "❌ ProGuard规则缺少MMKV保护"
    exit 1
fi

echo ""
echo "7. 检查依赖版本..."
MMKV_VERSION=$(grep "mmkv:" pubspec.yaml | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
echo "📋 Dart MMKV版本: $MMKV_VERSION"

NATIVE_MMKV=$(grep "com.tencent:mmkv" android/app/build.gradle | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
echo "📋 原生MMKV版本: $NATIVE_MMKV"

echo ""
echo "8. 检查GitHub Actions配置..."
if grep -q "android-arm" .github/workflows/flutter-release-build.yml; then
    echo "✅ CI配置包含32位ARM构建测试"
else
    echo "❌ CI配置缺少32位ARM测试"
    exit 1
fi

echo ""
echo "🎉 所有32位设备兼容性检查通过！"
echo ""
echo "注意事项："
echo "- 32位设备将自动使用SharedPreferences代替MMKV"
echo "- 应用已配置大堆内存以支持大文件处理"
echo "- CI流程会测试32位和64位APK构建"
echo "- 所有架构(armeabi-v7a, arm64-v8a, x86, x86_64)都会包含在APK中"
echo ""