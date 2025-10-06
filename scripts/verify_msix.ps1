#!/usr/bin/env pwsh
# MSIX 包验证脚本
# 用于检查构建的 MSIX 包是否符合 Microsoft Store 要求

param(
    [Parameter(Mandatory=$false)]
    [string]$MsixPath = ""
)

Write-Host "=== ThoughtEcho MSIX 包验证工具 ===" -ForegroundColor Cyan
Write-Host ""

# 如果未指定路径，尝试查找
if ([string]::IsNullOrEmpty($MsixPath)) {
    Write-Host "未指定 MSIX 路径，正在搜索..." -ForegroundColor Yellow
    
    $possiblePaths = @(
        "build/windows/x64/runner/Release/ThoughtEcho-Setup.msix",
        "build/windows/x64/runner/Release/thoughtecho.msix",
        "ThoughtEcho-Setup.msix",
        "thoughtecho.msix"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $MsixPath = $path
            Write-Host "✅ 找到 MSIX 文件: $MsixPath" -ForegroundColor Green
            break
        }
    }
    
    if ([string]::IsNullOrEmpty($MsixPath)) {
        Write-Host "❌ 未找到 MSIX 文件。请先构建 MSIX 包或指定路径。" -ForegroundColor Red
        Write-Host ""
        Write-Host "使用方法:" -ForegroundColor Yellow
        Write-Host "  .\scripts\verify_msix.ps1 -MsixPath 'path\to\package.msix'" -ForegroundColor Gray
        Write-Host "  或先运行: flutter pub run msix:create" -ForegroundColor Gray
        exit 1
    }
}

# 检查文件是否存在
if (!(Test-Path $MsixPath)) {
    Write-Host "❌ MSIX 文件不存在: $MsixPath" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "正在验证: $MsixPath" -ForegroundColor Cyan
Write-Host ""

# Microsoft Store 要求的正确值
$EXPECTED_IDENTITY_NAME = "Shangjinyun.330094822087A"
$EXPECTED_PUBLISHER = "CN=14B607B9-7CF3-42D9-9054-090F3ECEC1D7"
$EXPECTED_PUBLISHER_DISPLAY_NAME = "Shangjinyun"
$EXPECTED_PFN = "Shangjinyun.330094822087A_q4mj6h6cp1xbc"

# 创建临时目录解压 MSIX
$tempDir = Join-Path $env:TEMP "ThoughtEcho_MSIX_Verify_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Write-Host "📦 解压 MSIX 包..." -ForegroundColor Yellow
    
    # 复制 MSIX 为 ZIP 并解压
    $zipPath = Join-Path $tempDir "package.zip"
    Copy-Item $MsixPath $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
    
    # 读取 AppxManifest.xml
    $manifestPath = Join-Path $tempDir "AppxManifest.xml"
    if (!(Test-Path $manifestPath)) {
        Write-Host "❌ 未找到 AppxManifest.xml" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ 成功解压" -ForegroundColor Green
    Write-Host ""
    
    # 解析 XML
    [xml]$manifest = Get-Content $manifestPath
    $identity = $manifest.Package.Identity
    $properties = $manifest.Package.Properties
    
    # 提取关键信息
    $identityName = $identity.Name
    $publisher = $identity.Publisher
    $version = $identity.Version
    $publisherDisplayName = $properties.PublisherDisplayName
    
    # 计算 Package Family Name
    # 注意: PFN 的后缀是根据 Publisher 的哈希计算的，我们无法在此脚本中准确计算
    # 但可以提取实际的 PFN（如果有已安装的包）
    
    Write-Host "=== 包标识信息 ===" -ForegroundColor Cyan
    Write-Host ""
    
    # 验证 Identity Name
    Write-Host "Identity Name:" -NoNewline
    if ($identityName -eq $EXPECTED_IDENTITY_NAME) {
        Write-Host " ✅ $identityName" -ForegroundColor Green
    } else {
        Write-Host " ❌ $identityName" -ForegroundColor Red
        Write-Host "   预期值: $EXPECTED_IDENTITY_NAME" -ForegroundColor Yellow
    }
    
    # 验证 Publisher
    Write-Host "Publisher:" -NoNewline
    if ($publisher -eq $EXPECTED_PUBLISHER) {
        Write-Host " ✅ $publisher" -ForegroundColor Green
    } else {
        Write-Host " ❌ $publisher" -ForegroundColor Red
        Write-Host "   预期值: $EXPECTED_PUBLISHER" -ForegroundColor Yellow
    }
    
    # 验证 Publisher Display Name
    Write-Host "Publisher Display Name:" -NoNewline
    if ($publisherDisplayName -eq $EXPECTED_PUBLISHER_DISPLAY_NAME) {
        Write-Host " ✅ $publisherDisplayName" -ForegroundColor Green
    } else {
        Write-Host " ❌ $publisherDisplayName" -ForegroundColor Red
        Write-Host "   预期值: $EXPECTED_PUBLISHER_DISPLAY_NAME" -ForegroundColor Yellow
    }
    
    # 验证版本号格式
    Write-Host "Version:" -NoNewline
    if ($version -match '^\d+\.\d+\.\d+\.0$') {
        Write-Host " ✅ $version (格式正确)" -ForegroundColor Green
    } else {
        Write-Host " ❌ $version" -ForegroundColor Red
        Write-Host "   预期格式: x.x.x.0 (第四位必须为 0)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "=== 其他信息 ===" -ForegroundColor Cyan
    Write-Host "Display Name: $($properties.DisplayName)"
    Write-Host "Description: $($properties.Description)"
    
    # 检查权限
    $capabilities = $manifest.Package.Capabilities
    if ($capabilities) {
        Write-Host ""
        Write-Host "权限 (Capabilities):" -ForegroundColor Cyan
        foreach ($cap in $capabilities.ChildNodes) {
            if ($cap.Name) {
                Write-Host "  - $($cap.Name)" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host ""
    Write-Host "=== 验证摘要 ===" -ForegroundColor Cyan
    Write-Host ""
    
    $allValid = $true
    $issues = @()
    
    if ($identityName -ne $EXPECTED_IDENTITY_NAME) {
        $allValid = $false
        $issues += "Identity Name 不匹配"
    }
    
    if ($publisher -ne $EXPECTED_PUBLISHER) {
        $allValid = $false
        $issues += "Publisher 不匹配（这会导致 PFN 不匹配）"
    }
    
    if ($publisherDisplayName -ne $EXPECTED_PUBLISHER_DISPLAY_NAME) {
        $allValid = $false
        $issues += "Publisher Display Name 不匹配"
    }
    
    if ($version -notmatch '^\d+\.\d+\.\d+\.0$') {
        $allValid = $false
        $issues += "版本号格式不符合 Store 要求"
    }
    
    if ($allValid) {
        Write-Host "✅ 所有验证通过！此 MSIX 包应该可以通过 Microsoft Store 检查。" -ForegroundColor Green
        Write-Host ""
        Write-Host "📤 可以安全提交到 Microsoft Store" -ForegroundColor Cyan
    } else {
        Write-Host "❌ 发现以下问题:" -ForegroundColor Red
        Write-Host ""
        foreach ($issue in $issues) {
            Write-Host "  • $issue" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "📖 请查看 docs/MSIX_STORE_SUBMISSION_FIX.md 了解解决方案" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Host "=== 完整 AppxManifest.xml (Identity 部分) ===" -ForegroundColor Cyan
    Write-Host ""
    
    # 显示 Identity 节点的完整 XML
    $identityXml = $manifest.Package.Identity.OuterXml
    Write-Host $identityXml -ForegroundColor Gray
    
} catch {
    Write-Host "❌ 验证过程出错: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    # 清理临时目录
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "验证完成。" -ForegroundColor Cyan
