# 本地Windows构建测试脚本
# 用于验证构建配置是否正确

Write-Host "开始本地Windows构建测试..." -ForegroundColor Green

# 检查Flutter环境
Write-Host "`n1. 检查Flutter环境..." -ForegroundColor Yellow
flutter doctor -v

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter环境检查失败"
    exit 1
}

# 启用Windows桌面支持
Write-Host "`n2. 启用Windows桌面支持..." -ForegroundColor Yellow
flutter config --enable-windows-desktop

# 获取依赖
Write-Host "`n3. 获取项目依赖..." -ForegroundColor Yellow
flutter pub get

if ($LASTEXITCODE -ne 0) {
    Write-Error "依赖获取失败"
    exit 1
}

# 清理之前的构建
Write-Host "`n4. 清理之前的构建产物..." -ForegroundColor Yellow
flutter clean

# 构建Windows应用
Write-Host "`n5. 构建Windows应用..." -ForegroundColor Yellow
flutter build windows --release --verbose

if ($LASTEXITCODE -ne 0) {
    Write-Error "Windows应用构建失败"
    exit 1
}

# 检查构建产物
$exePath = "build/windows/x64/runner/Release/thoughtecho.exe"
if (Test-Path $exePath) {
    $fileInfo = Get-ItemProperty $exePath
    Write-Host "`n✅ Windows应用构建成功!" -ForegroundColor Green
    Write-Host "   文件路径: $exePath" -ForegroundColor Gray
    Write-Host "   文件大小: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Gray
    Write-Host "   修改时间: $($fileInfo.LastWriteTime)" -ForegroundColor Gray
} else {
    Write-Error "构建的exe文件不存在: $exePath"
    exit 1
}

# 尝试构建MSIX（可选）
Write-Host "`n6. 尝试构建MSIX安装包..." -ForegroundColor Yellow
Write-Host "注意：如果提示安装证书，请选择 'n' (不安装)" -ForegroundColor Red

try {
    flutter pub run msix:create
    
    $msixPath = "build/windows/x64/runner/Release/ThoughtEcho-Setup.msix"
    if (Test-Path $msixPath) {
        $msixInfo = Get-ItemProperty $msixPath
        Write-Host "`n✅ MSIX安装包构建成功!" -ForegroundColor Green
        Write-Host "   文件路径: $msixPath" -ForegroundColor Gray
        Write-Host "   文件大小: $([math]::Round($msixInfo.Length / 1MB, 2)) MB" -ForegroundColor Gray
    } else {
        Write-Warning "MSIX文件未找到，可能构建失败"
    }
}
catch {
    Write-Warning "MSIX构建失败: $_"
    Write-Host "这在CI环境中是正常的，主要的exe文件已经构建成功" -ForegroundColor Gray
}

Write-Host "`n🎉 构建测试完成!" -ForegroundColor Green
Write-Host "Windows应用可以在以下路径找到: $exePath" -ForegroundColor Cyan

# 询问是否启动应用测试
$response = Read-Host "`n是否要启动应用进行测试? (y/N)"
if ($response -eq 'y' -or $response -eq 'Y') {
    Write-Host "启动应用..." -ForegroundColor Yellow
    Start-Process $exePath
}
