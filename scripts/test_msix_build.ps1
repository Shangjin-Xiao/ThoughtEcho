# ThoughtEcho MSIX 构建测试脚本
# 用于本地测试MSIX构建流程

param(
    [string]$BuildType = "release",
    [string]$Version = "1.0.0"
)

Write-Host "=== ThoughtEcho MSIX 构建测试 ===" -ForegroundColor Green
Write-Host "构建类型: $BuildType" -ForegroundColor Yellow
Write-Host "版本号: $Version" -ForegroundColor Yellow
Write-Host ""

# 检查环境
Write-Host "1. 检查环境..." -ForegroundColor Cyan
if (!(Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter 未安装或未在PATH中"
    exit 1
}

if (!(Test-Path "pubspec.yaml")) {
    Write-Error "当前目录不是Flutter项目根目录"
    exit 1
}

if (!(Test-Path "msix_config.yaml")) {
    Write-Warning "msix_config.yaml 不存在，请确保已正确配置"
}

# 检查MSIX插件
Write-Host "2. 检查MSIX插件..." -ForegroundColor Cyan
$pubspecContent = Get-Content "pubspec.yaml" -Raw
if ($pubspecContent -notmatch "msix:") {
    Write-Error "pubspec.yaml 中未找到 msix 依赖"
    exit 1
}

# 获取依赖
Write-Host "3. 获取依赖..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter pub get 失败"
    exit 1
}

# 清理之前的构建
Write-Host "4. 清理之前的构建..." -ForegroundColor Cyan
flutter clean

# 构建Windows应用
Write-Host "5. 构建Windows应用..." -ForegroundColor Cyan
flutter build windows --$BuildType --verbose
if ($LASTEXITCODE -ne 0) {
    Write-Error "Windows应用构建失败"
    exit 1
}

# 检查构建结果
$buildPath = if ($BuildType -eq "release") { "build/windows/x64/runner/Release" } else { "build/windows/x64/runner/Profile" }
if (!(Test-Path "$buildPath/thoughtecho.exe")) {
    Write-Error "Windows构建文件不存在: $buildPath/thoughtecho.exe"
    exit 1
}

Write-Host "✅ Windows应用构建成功" -ForegroundColor Green

# 构建MSIX包
Write-Host "6. 构建MSIX包..." -ForegroundColor Cyan
try {
    # 设置环境变量
    $env:FLUTTER_SUPPRESS_ANALYTICS = "true"
    
    # 构建MSIX
    $msixResult = flutter pub run msix:create 2>&1
    $msixExitCode = $LASTEXITCODE
    
    Write-Host "MSIX构建输出:" -ForegroundColor Yellow
    Write-Host $msixResult
    
    if ($msixExitCode -eq 0) {
        # 检查MSIX文件
        $msixPath = "build/windows/x64/runner/Release/ThoughtEcho-Setup.msix"
        if (Test-Path $msixPath) {
            $msixSize = (Get-Item $msixPath).Length
            Write-Host "✅ MSIX构建成功！" -ForegroundColor Green
            Write-Host "文件路径: $msixPath" -ForegroundColor Green
            Write-Host "文件大小: $([math]::Round($msixSize/1MB, 2)) MB" -ForegroundColor Green
        } else {
            Write-Warning "⚠️ MSIX命令执行成功但文件未找到: $msixPath"
            
            # 列出可能的MSIX文件
            Write-Host "寻找其他MSIX文件..." -ForegroundColor Yellow
            Get-ChildItem -Recurse -Filter "*.msix" | ForEach-Object {
                Write-Host "找到MSIX文件: $($_.FullName)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Error "⚠️ MSIX构建失败（退出码: $msixExitCode）"
        Write-Host "错误输出: $msixResult" -ForegroundColor Red
    }
}
catch {
    Write-Error "⚠️ MSIX构建异常: $_"
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""
Write-Host "=== 测试完成 ===" -ForegroundColor Green
