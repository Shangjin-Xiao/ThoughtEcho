#!/bin/bash
# ThoughtEcho AI Streaming Refactoring Mission - Environment Setup
# This script is idempotent and safe to run multiple times.

set -e

echo "=== ThoughtEcho Mission Init ==="

# Install dependencies
echo "Installing Flutter dependencies..."
flutter pub get

# Generate localization files if needed
if [ ! -f "lib/gen_l10n/app_localizations.dart" ] || [ "lib/l10n/app_zh.arb" -nt "lib/gen_l10n/app_localizations.dart" ]; then
  echo "Generating localization files..."
  flutter gen-l10n
fi

# Generate mocks if needed
if [ ! -f "test/test_setup.mocks.dart" ] || [ "test/test_setup.dart" -nt "test/test_setup.mocks.dart" ]; then
  echo "Generating mocks..."
  dart run build_runner build --delete-conflicting-outputs 2>/dev/null || true
fi

# Verify openai_dart is available
echo "Verifying openai_dart dependency..."
flutter pub deps | grep openai_dart || echo "WARNING: openai_dart not found in dependencies"

# Verify Ollama availability (optional)
if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
  echo "Ollama is running at localhost:11434"
else
  echo "Ollama is not running. Start with: ollama serve"
  echo "Integration tests requiring Ollama will be skipped."
fi

echo "=== Init complete ==="
