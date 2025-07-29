@echo off
chcp 65001 > nul
title ThoughtEcho Windows构建测试

echo.
echo ==========================================
echo   ThoughtEcho Windows构建测试脚本
echo ==========================================
echo.

echo [1/5] 检查Flutter环境...
flutter doctor -v
if %errorlevel% neq 0 (
    echo.
    echo ❌ Flutter环境检查失败，请先安装并配置Flutter
    echo    下载地址: https://flutter.dev/docs/get-started/install/windows
    pause
    exit /b 1
)

echo.
echo [2/5] 启用Windows桌面支持...
flutter config --enable-windows-desktop

echo.
echo [3/5] 获取项目依赖...
flutter pub get
if %errorlevel% neq 0 (
    echo.
    echo ❌ 依赖获取失败
    pause
    exit /b 1
)

echo.
echo [4/5] 清理之前的构建...
flutter clean

echo.
echo [5/5] 构建Windows应用...
flutter build windows --release --verbose
if %errorlevel% neq 0 (
    echo.
    echo ❌ Windows应用构建失败
    pause
    exit /b 1
)

echo.
echo ✅ Windows应用构建成功！
echo.

set "EXE_PATH=build\windows\x64\runner\Release\thoughtecho.exe"
if exist "%EXE_PATH%" (
    echo 📁 应用位置: %EXE_PATH%
    
    for %%A in ("%EXE_PATH%") do (
        set "SIZE=%%~zA"
        set /a "SIZE_MB=%%~zA / 1048576"
    )
    echo 📊 文件大小: %SIZE_MB% MB
    
    echo.
    echo 🎯 构建测试完成！
    echo.
    set /p "LAUNCH=是否要启动应用进行测试？(Y/N): "
    if /i "%LAUNCH%"=="Y" (
        echo.
        echo 🚀 启动应用...
        start "" "%EXE_PATH%"
    )
) else (
    echo ❌ 构建的exe文件不存在: %EXE_PATH%
    pause
    exit /b 1
)

echo.
echo 📝 提示：
echo    - 首次启动可能需要等待数秒
echo    - 如遇问题请检查Windows Defender或杀毒软件设置
echo    - 确保系统已安装Visual C++ Redistributable
echo.
pause
