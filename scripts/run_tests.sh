#!/bin/bash

# ThoughtEcho Test Runner Script
# 使用方法: ./scripts/run_tests.sh [options]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Default options
RUN_UNIT_TESTS=true
RUN_WIDGET_TESTS=true
RUN_INTEGRATION_TESTS=false
GENERATE_COVERAGE=true
GENERATE_MOCKS=false
CLEAN_BUILD=false
VERBOSE=false
PLATFORM=""

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "${WHITE}$1${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
🧪 ThoughtEcho Test Runner

使用方法: $0 [选项]

选项:
  -u, --unit-tests          只运行单元测试 (默认: 开启)
  -w, --widget-tests        只运行Widget测试 (默认: 开启)
  -i, --integration-tests   运行集成测试 (默认: 关闭)
  -c, --coverage            生成代码覆盖率报告 (默认: 开启)
  -m, --generate-mocks      生成Mock文件
  -g, --clean               清理构建缓存
  -v, --verbose             详细输出
  -p, --platform PLATFORM  指定测试平台 (chrome, flutter-tester)
  -a, --all                 运行所有测试（包括集成测试）
  --no-coverage             不生成覆盖率报告
  --no-unit                 跳过单元测试
  --no-widget               跳过Widget测试
  -h, --help                显示此帮助信息

示例:
  $0                        # 运行默认测试套件
  $0 -a                     # 运行所有测试
  $0 -i -p chrome           # 在Chrome中运行集成测试
  $0 -m -g                  # 生成Mock文件并清理构建
  $0 --no-coverage -v       # 运行测试但不生成覆盖率，详细输出
  
覆盖率报告将生成在 coverage/ 目录中。
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--unit-tests)
            RUN_UNIT_TESTS=true
            RUN_WIDGET_TESTS=false
            RUN_INTEGRATION_TESTS=false
            shift
            ;;
        -w|--widget-tests)
            RUN_UNIT_TESTS=false
            RUN_WIDGET_TESTS=true
            RUN_INTEGRATION_TESTS=false
            shift
            ;;
        -i|--integration-tests)
            RUN_INTEGRATION_TESTS=true
            shift
            ;;
        -c|--coverage)
            GENERATE_COVERAGE=true
            shift
            ;;
        --no-coverage)
            GENERATE_COVERAGE=false
            shift
            ;;
        --no-unit)
            RUN_UNIT_TESTS=false
            shift
            ;;
        --no-widget)
            RUN_WIDGET_TESTS=false
            shift
            ;;
        -m|--generate-mocks)
            GENERATE_MOCKS=true
            shift
            ;;
        -g|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -p|--platform)
            PLATFORM="$2"
            shift 2
            ;;
        -a|--all)
            RUN_UNIT_TESTS=true
            RUN_WIDGET_TESTS=true
            RUN_INTEGRATION_TESTS=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "未知选项: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    print_error "Flutter 未安装或不在 PATH 中"
    print_info "请安装 Flutter: https://flutter.dev/docs/get-started/install"
    exit 1
fi

print_header "🧪 ThoughtEcho 测试运行器"
print_info "Flutter 版本: $(flutter --version | head -n 1)"

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

print_info "项目目录: $PROJECT_ROOT"

# Clean build if requested
if [ "$CLEAN_BUILD" = true ]; then
    print_info "清理构建缓存..."
    flutter clean
    rm -rf coverage/
    rm -rf test_results/
fi

# Get dependencies
print_info "获取依赖..."
flutter pub get

# Generate mocks if requested
if [ "$GENERATE_MOCKS" = true ]; then
    print_info "生成 Mock 文件..."
    if ! flutter packages pub run build_runner build --delete-conflicting-outputs; then
        print_warning "Mock 文件生成失败，继续执行测试..."
    else
        print_success "Mock 文件生成完成"
    fi
fi

# Prepare test command options
TEST_OPTIONS=""
if [ "$VERBOSE" = true ]; then
    TEST_OPTIONS="$TEST_OPTIONS --reporter=expanded"
fi

if [ "$GENERATE_COVERAGE" = true ]; then
    TEST_OPTIONS="$TEST_OPTIONS --coverage"
fi

# Run unit tests
if [ "$RUN_UNIT_TESTS" = true ]; then
    print_header "🔧 运行单元测试..."
    if flutter test test/unit/ $TEST_OPTIONS; then
        print_success "单元测试通过"
    else
        print_error "单元测试失败"
        exit 1
    fi
fi

# Run widget tests
if [ "$RUN_WIDGET_TESTS" = true ]; then
    print_header "🎨 运行 Widget 测试..."
    if [ -d "test/widget" ] && [ "$(find test/widget -name "*.dart" | wc -l)" -gt 0 ]; then
        if flutter test test/widget/ $TEST_OPTIONS; then
            print_success "Widget 测试通过"
        else
            print_error "Widget 测试失败"
            exit 1
        fi
    else
        print_warning "未找到 Widget 测试文件，跳过..."
    fi
fi

# Run integration tests
if [ "$RUN_INTEGRATION_TESTS" = true ]; then
    print_header "🔗 运行集成测试..."
    
    INTEGRATION_OPTIONS=""
    if [ -n "$PLATFORM" ]; then
        case $PLATFORM in
            chrome)
                INTEGRATION_OPTIONS="--platform chrome"
                ;;
            flutter-tester)
                INTEGRATION_OPTIONS="--device-id flutter-tester"
                ;;
            *)
                print_warning "未知平台: $PLATFORM，使用默认设置"
                ;;
        esac
    fi
    
    if [ -d "integration_test" ] && [ "$(find integration_test -name "*.dart" | wc -l)" -gt 0 ]; then
        if flutter test integration_test/ $INTEGRATION_OPTIONS; then
            print_success "集成测试通过"
        else
            print_error "集成测试失败"
            exit 1
        fi
    else
        print_warning "未找到集成测试文件，跳过..."
    fi
fi

# Generate coverage report
if [ "$GENERATE_COVERAGE" = true ] && [ -f "coverage/lcov.info" ]; then
    print_header "📊 生成覆盖率报告..."
    
    # Check if lcov is available for HTML report generation
    if command -v genhtml &> /dev/null; then
        print_info "生成 HTML 覆盖率报告..."
        genhtml coverage/lcov.info -o coverage/html --ignore-errors source
        print_success "HTML 覆盖率报告已生成: coverage/html/index.html"
        
        # Show coverage summary
        if command -v lcov &> /dev/null; then
            print_info "覆盖率摘要:"
            lcov --summary coverage/lcov.info
        fi
    else
        print_warning "lcov 未安装，无法生成 HTML 报告"
        print_info "LCOV 数据已保存到: coverage/lcov.info"
        print_info "要生成 HTML 报告，请安装 lcov:"
        print_info "  Ubuntu/Debian: sudo apt-get install lcov"
        print_info "  macOS: brew install lcov"
    fi
fi

print_header "🎉 测试完成！"

# Show summary
echo
print_info "测试摘要:"
if [ "$RUN_UNIT_TESTS" = true ]; then
    echo "  ✅ 单元测试: 已运行"
fi
if [ "$RUN_WIDGET_TESTS" = true ]; then
    echo "  ✅ Widget测试: 已运行"
fi
if [ "$RUN_INTEGRATION_TESTS" = true ]; then
    echo "  ✅ 集成测试: 已运行"
fi
if [ "$GENERATE_COVERAGE" = true ]; then
    echo "  ✅ 代码覆盖率: 已生成"
fi

echo
print_info "更多测试选项，请运行: $0 --help"