#!/bin/bash

# iOS 本地构建脚本（无签名版本）
# 用于验证代码能否成功编译

set -e

echo "🚀 开始 iOS 构建..."

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 检查是否在 macOS 上
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}❌ 此脚本只能在 macOS 上运行${NC}"
    exit 1
fi

# 清理之前的构建
echo -e "${YELLOW}🧹 清理之前的构建...${NC}"
flutter clean

# 获取依赖
echo -e "${YELLOW}📦 获取依赖...${NC}"
flutter pub get

# 运行代码分析
echo -e "${YELLOW}🔍 运行代码分析...${NC}"
flutter analyze --no-fatal-infos || echo -e "${YELLOW}⚠️  存在一些警告，继续构建...${NC}"

# 构建 iOS（无签名）
echo -e "${YELLOW}🔨 构建 iOS 应用（无签名）...${NC}"
flutter build ios --release --no-codesign --no-tree-shake-icons

# 检查构建结果
if [ -d "build/ios/iphoneos/Runner.app" ]; then
    echo -e "${GREEN}✅ 构建成功！${NC}"
    echo -e "${GREEN}📱 应用位置: build/ios/iphoneos/Runner.app${NC}"
    
    # 显示应用大小
    APP_SIZE=$(du -sh build/ios/iphoneos/Runner.app | cut -f1)
    echo -e "${GREEN}📊 应用大小: $APP_SIZE${NC}"
    
    # 创建 IPA（未签名）
    echo -e "${YELLOW}📦 创建未签名 IPA...${NC}"
    mkdir -p build/ipa/Payload
    cp -r build/ios/iphoneos/Runner.app build/ipa/Payload/
    cd build/ipa
    zip -r ThoughtEcho-unsigned.ipa Payload > /dev/null
    cd ../..
    
    IPA_SIZE=$(du -sh build/ipa/ThoughtEcho-unsigned.ipa | cut -f1)
    echo -e "${GREEN}✅ IPA 创建成功！${NC}"
    echo -e "${GREEN}📦 IPA 位置: build/ipa/ThoughtEcho-unsigned.ipa${NC}"
    echo -e "${GREEN}📊 IPA 大小: $IPA_SIZE${NC}"
    
    echo ""
    echo -e "${YELLOW}ℹ️  注意事项：${NC}"
    echo "  • 此 IPA 未签名，无法直接安装到真机"
    echo "  • 可以用于验证构建流程"
    echo "  • 需要开发者账号才能签名和安装"
    echo ""
    echo -e "${GREEN}🎉 所有步骤完成！${NC}"
else
    echo -e "${RED}❌ 构建失败，请检查错误信息${NC}"
    exit 1
fi
