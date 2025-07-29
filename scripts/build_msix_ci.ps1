# PowerShell脚本用于在CI环境中构建MSIX包
# 解决交互式证书安装问题

param(
    [string]$BuildType = "release"
)

Write-Host "开始构建MSIX安装包..."

# 设置环境变量，禁用交互式提示
$env:MSIX_SILENT = "true"
$env:CI = "true"
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"

try {
    # 首先检查Flutter是否正确配置
    Write-Host "检查Flutter配置..."
    flutter doctor --suppress-analytics

    # 清理之前的构建产物
    Write-Host "清理之前的构建产物..."
    if (Test-Path "build/windows") {
        Remove-Item "build/windows" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 重新获取依赖
    Write-Host "获取依赖..."
    flutter pub get

    # 构建Windows应用
    Write-Host "构建Windows应用 ($BuildType)..."
    $buildCmd = "flutter build windows --$BuildType --verbose"
    Invoke-Expression $buildCmd
    
    if ($LASTEXITCODE -ne 0) {
        throw "Windows应用构建失败"
    }

    # 检查构建产物是否存在
    $buildPath = if ($BuildType -eq "release") { "build/windows/x64/runner/Release" } else { "build/windows/x64/runner/Profile" }
    $exePath = "$buildPath/thoughtecho.exe"
    
    if (!(Test-Path $exePath)) {
        throw "构建的exe文件不存在: $exePath"
    }
    
    Write-Host "Windows应用构建成功: $exePath"

    # 尝试构建MSIX包
    Write-Host "开始构建MSIX包..."
    
    # 方法1: 尝试使用环境变量控制非交互模式
    Write-Host "方法1: 使用环境变量控制..."
    try {
        $originalInput = $env:INPUT
        $env:INPUT = "n"  # 自动回答 'n' 给证书安装提示
        flutter pub run msix:create 2>&1 | ForEach-Object { Write-Host $_ }
        $env:INPUT = $originalInput
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "方法1成功"
        } else {
            throw "方法1失败"
        }
    }
    catch {
        Write-Host "方法1失败: $_"
        
        # 方法2: 使用PowerShell的输入重定向
        Write-Host "方法2: 使用输入重定向..."
        try {
            $process = Start-Process -FilePath "flutter" -ArgumentList "pub", "run", "msix:create" -NoNewWindow -Wait -PassThru -RedirectStandardInput "NUL"
            if ($process.ExitCode -ne 0) {
                throw "方法2失败，退出码: $($process.ExitCode)"
            }
            Write-Host "方法2成功"
        }
        catch {
            Write-Host "方法2失败: $_"
            
            # 方法3: 最后的回退 - 只构建Windows exe，跳过MSIX
            Write-Host "所有MSIX构建方法失败，将只提供exe文件"
            return $false
        }
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "MSIX构建失败，但Windows应用构建成功"
        Write-Host "可以继续使用exe文件进行发布"
        return $false
    }

    # 检查MSIX文件是否生成
    $msixPath = "$buildPath/ThoughtEcho-Setup.msix"
    if (Test-Path $msixPath) {
        Write-Host "MSIX包构建成功: $msixPath"
        return $true
    } else {
        Write-Warning "MSIX文件未找到，但构建过程未报错"
        return $false
    }
}
catch {
    Write-Error "构建过程中发生错误: $_"
    return $false
}
