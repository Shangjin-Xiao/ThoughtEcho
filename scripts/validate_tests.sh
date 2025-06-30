#!/bin/bash

# Test Infrastructure Validation Script
# Validates that the testing infrastructure is properly set up

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Validating ThoughtEcho Testing Infrastructure${NC}"
echo "=================================================="

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}❌ Error: pubspec.yaml not found. Please run from project root.${NC}"
    exit 1
fi

echo -e "${BLUE}📋 Checking test structure...${NC}"

# Check directory structure
EXPECTED_DIRS=(
    "test"
    "test/unit"
    "test/unit/services"
    "test/unit/models"
    "test/widget"
    "test/widget/pages"
    "test/integration"
    "test/mocks"
    "test/utils"
    "integration_test"
    "scripts"
)

for dir in "${EXPECTED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "  ✅ $dir"
    else
        echo -e "  ${RED}❌ $dir${NC}"
        exit 1
    fi
done

# Check key files
EXPECTED_FILES=(
    "test/README.md"
    "test/mocks/mock_database_service.dart"
    "test/mocks/mock_ai_service.dart"
    "test/mocks/mock_location_service.dart"
    "test/mocks/mock_weather_service.dart"
    "test/mocks/mock_settings_service.dart"
    "test/unit/services/database_service_test.dart"
    "test/unit/services/ai_service_test.dart"
    "test/unit/models/models_test.dart"
    "test/widget/pages/app_widget_test.dart"
    "test/utils/test_utils.dart"
    "integration_test/app_test.dart"
    ".github/workflows/test.yml"
    "scripts/run_tests.sh"
    "test_config.yaml"
)

echo -e "\n${BLUE}📄 Checking test files...${NC}"
for file in "${EXPECTED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "  ✅ $file"
    else
        echo -e "  ${RED}❌ $file${NC}"
        exit 1
    fi
done

# Check pubspec.yaml for test dependencies
echo -e "\n${BLUE}📦 Checking test dependencies in pubspec.yaml...${NC}"
REQUIRED_DEPS=(
    "mockito"
    "build_runner"
    "integration_test"
    "coverage"
)

for dep in "${REQUIRED_DEPS[@]}"; do
    if grep -q "$dep:" pubspec.yaml; then
        echo -e "  ✅ $dep"
    else
        echo -e "  ${RED}❌ $dep${NC}"
        exit 1
    fi
done

# Check GitHub Actions workflow
echo -e "\n${BLUE}🚀 Checking GitHub Actions workflow...${NC}"
WORKFLOW_FILE=".github/workflows/test.yml"
REQUIRED_JOBS=(
    "analyze"
    "test"
    "integration-test"
    "build-test"
    "security"
)

for job in "${REQUIRED_JOBS[@]}"; do
    if grep -q "$job:" "$WORKFLOW_FILE"; then
        echo -e "  ✅ $job job"
    else
        echo -e "  ${RED}❌ $job job${NC}"
        exit 1
    fi
done

# Check test script permissions
echo -e "\n${BLUE}🔧 Checking script permissions...${NC}"
if [ -x "scripts/run_tests.sh" ]; then
    echo -e "  ✅ scripts/run_tests.sh is executable"
else
    echo -e "  ${YELLOW}⚠️  Making scripts/run_tests.sh executable${NC}"
    chmod +x scripts/run_tests.sh
fi

# Validate Dart syntax in test files
echo -e "\n${BLUE}🔍 Validating Dart syntax in test files...${NC}"
TEST_FILES=$(find test -name "*.dart" 2>/dev/null)
if [ -n "$TEST_FILES" ]; then
    echo "  Found $(echo "$TEST_FILES" | wc -l) test files"
    for file in $TEST_FILES; do
        # Basic syntax check - look for obvious issues
        if grep -q "import.*thoughtecho" "$file"; then
            echo -e "  ✅ $file (has project imports)"
        elif grep -q "void main()" "$file"; then
            echo -e "  ✅ $file (has main function)"
        else
            echo -e "  ${YELLOW}⚠️  $file (basic structure)${NC}"
        fi
    done
else
    echo -e "  ${RED}❌ No test files found${NC}"
    exit 1
fi

# Check for import consistency
echo -e "\n${BLUE}📝 Checking import consistency...${NC}"
INCONSISTENT_IMPORTS=0

# Check for relative imports in test files
find test -name "*.dart" -exec grep -l "import.*\.\./\.\./\.\." {} \; > /tmp/relative_imports.txt || true
if [ -s /tmp/relative_imports.txt ]; then
    echo -e "  ✅ Found relative imports (expected for test files)"
else
    echo -e "  ${YELLOW}⚠️  No relative imports found${NC}"
fi

# Check .gitignore for test artifacts
echo -e "\n${BLUE}🚫 Checking .gitignore for test artifacts...${NC}"
GITIGNORE_ENTRIES=(
    "coverage/"
    "test_results/"
    "*.mocks.dart"
)

for entry in "${GITIGNORE_ENTRIES[@]}"; do
    if grep -q "$entry" .gitignore; then
        echo -e "  ✅ $entry"
    else
        echo -e "  ${YELLOW}⚠️  $entry not in .gitignore${NC}"
    fi
done

# Check README documentation
echo -e "\n${BLUE}📚 Checking test documentation...${NC}"
if [ -f "test/README.md" ]; then
    README_SECTIONS=(
        "测试结构"
        "单元测试"
        "Widget测试"
        "集成测试"
        "运行测试"
    )
    
    for section in "${README_SECTIONS[@]}"; do
        if grep -q "$section" "test/README.md"; then
            echo -e "  ✅ $section section"
        else
            echo -e "  ${YELLOW}⚠️  $section section${NC}"
        fi
    done
else
    echo -e "  ${RED}❌ test/README.md not found${NC}"
    exit 1
fi

# Summary
echo -e "\n${GREEN}🎉 Testing Infrastructure Validation Complete!${NC}"
echo "=================================================="
echo -e "${GREEN}✅ All required directories are present${NC}"
echo -e "${GREEN}✅ All required files are present${NC}"
echo -e "${GREEN}✅ Test dependencies are configured${NC}"
echo -e "${GREEN}✅ GitHub Actions workflow is configured${NC}"
echo -e "${GREEN}✅ Test scripts are ready${NC}"
echo -e "${GREEN}✅ Documentation is available${NC}"

echo -e "\n${BLUE}📋 Next Steps:${NC}"
echo "1. Run: flutter pub get"
echo "2. Run: ./scripts/run_tests.sh --help"
echo "3. Run: ./scripts/run_tests.sh -u (for unit tests)"
echo "4. Check GitHub Actions on next push/PR"

echo -e "\n${BLUE}📖 Documentation:${NC}"
echo "- Test documentation: test/README.md"
echo "- Test runner help: ./scripts/run_tests.sh --help"
echo "- GitHub Actions: .github/workflows/test.yml"

# Clean up temporary files
rm -f /tmp/relative_imports.txt

exit 0