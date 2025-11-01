#!/bin/bash

# ThoughtEcho iOS 无签名构建脚本

set -e

echo "=========================================="
echo "ThoughtEcho iOS 无签名构建脚本"
echo "=========================================="
echo ""

if [ ! -f "pubspec.yaml" ]; then
    echo "❌ 错误: 请在项目根目录运行此脚本"
    exit 1
fi

echo "📦 步骤 1/5: 清理旧构建..."
flutter clean

echo "📦 步骤 2/5: 安装依赖..."
flutter pub get

echo "📦 步骤 3/5: 代码分析..."
flutter analyze --no-fatal-infos || echo "⚠️  代码分析有警告，继续构建..."

echo "📦 步骤 4/5: 构建 iOS 应用 (无签名)..."
flutter build ios --release --no-codesign --no-tree-shake-icons

echo "📦 步骤 5/5: 创建 IPA 文件..."
rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -r build/ios/iphoneos/Runner.app build/ipa/Payload/
cd build/ipa
zip -qr ThoughtEcho-unsigned.ipa Payload
cd ../..

IPA_SIZE=$(du -h build/ipa/ThoughtEcho-unsigned.ipa | cut -f1)

echo ""
echo "=========================================="
echo "✅ 构建完成！"
echo "=========================================="
echo ""
echo "📱 IPA 位置: build/ipa/ThoughtEcho-unsigned.ipa"
echo "📊 文件大小: $IPA_SIZE"
echo ""
echo "📝 安装方法:"
echo "  1. 使用 AltStore (https://altstore.io)"
echo "  2. 使用 Sideloadly (https://sideloadly.io)"
echo "  3. 使用开发者账号签名后安装"
echo ""
echo "📖 详细说明: docs/iOS-发布完整指南.md"
echo ""
