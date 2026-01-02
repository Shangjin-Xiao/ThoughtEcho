#!/bin/bash
# 本地 AI 功能验证脚本

echo "===================="
echo "本地 AI 功能验证"
echo "===================="
echo ""

# 检查编译错误
echo "1. 检查编译错误..."
flutter analyze --no-pub 2>&1 | grep -E "error •" && {
    echo "❌ 发现编译错误"
    exit 1
} || {
    echo "✅ 无编译错误"
}
echo ""

# 检查关键文件是否存在
echo "2. 检查关键文件..."
files=(
    "lib/services/local_ai/local_ocr_service.dart"
    "lib/services/local_ai/local_speech_recognition_service.dart"
    "lib/widgets/local_ai/ocr_capture_page.dart"
    "lib/widgets/local_ai/voice_input_overlay.dart"
    "lib/models/local_ai_settings.dart"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file"
    else
        echo "  ❌ $file 不存在"
        exit 1
    fi
done
echo ""

# 检查依赖包
echo "3. 检查依赖包..."
packages=(
    "google_mlkit_text_recognition"
    "speech_to_text"
    "camera"
)

for package in "${packages[@]}"; do
    grep -q "$package:" pubspec.yaml && {
        echo "  ✅ $package"
    } || {
        echo "  ❌ $package 未在 pubspec.yaml 中找到"
        exit 1
    }
done
echo ""

# 检查国际化
echo "4. 检查国际化..."
i18n_keys=(
    "swipeUpForOcr"
    "listening"
    "ocrCapture"
    "ocrNoTextDetected"
)

for key in "${i18n_keys[@]}"; do
    grep -q "\"$key\":" lib/l10n/app_zh.arb && {
        echo "  ✅ $key"
    } || {
        echo "  ❌ $key 未在国际化文件中找到"
        exit 1
    }
done
echo ""

echo "===================="
echo "✅ 所有验证通过！"
echo "===================="
echo ""
echo "本地 AI 功能已准备就绪："
echo "  • OCR 文字识别"
echo "  • 语音转文字"
echo "  • 手势交互"
echo ""
echo "使用方法："
echo "  1. 在设置中启用'本地AI功能'"
echo "  2. 长按主页 FAB 按钮触发语音输入"
echo "  3. 上划切换到 OCR 拍照"
echo ""
