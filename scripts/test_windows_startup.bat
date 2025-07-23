@echo off
echo =================================
echo ThoughtEcho Windows 启动测试脚本
echo =================================
echo.

echo 1. 清理之前的调试文件...
if exist "%USERPROFILE%\Desktop\ThoughtEcho_*" (
    del /q "%USERPROFILE%\Desktop\ThoughtEcho_*"
    echo 已清理桌面调试文件
)

echo.
echo 2. 检查系统要求...
echo 操作系统: %OS%
echo 处理器架构: %PROCESSOR_ARCHITECTURE%
echo 用户名: %USERNAME%

echo.
echo 3. 检查Visual C++ Redistributable...
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" >nul 2>&1
if %errorlevel% equ 0 (
    echo ✓ Visual C++ Redistributable x64 已安装
) else (
    echo ✗ Visual C++ Redistributable x64 未找到
    echo   请从以下地址下载安装: https://aka.ms/vs/17/release/vc_redist.x64.exe
)

echo.
echo 4. 启动应用并监控...
echo 启动时间: %date% %time%
echo 正在启动 ThoughtEcho...

:: 启动应用
start "" "build\windows\runner\Release\thoughtecho.exe"

:: 等待5秒
timeout /t 5 /nobreak >nul

echo.
echo 5. 检查进程状态...
tasklist /fi "imagename eq thoughtecho.exe" | find /i "thoughtecho.exe" >nul
if %errorlevel% equ 0 (
    echo ✓ ThoughtEcho 进程正在运行
    
    :: 显示内存使用情况
    echo.
    echo 内存使用情况:
    tasklist /fi "imagename eq thoughtecho.exe" /fo table
) else (
    echo ✗ ThoughtEcho 进程未找到
    echo   应用可能启动失败或已崩溃
)

echo.
echo 6. 检查调试文件...
if exist "%USERPROFILE%\Desktop\ThoughtEcho_*" (
    echo ✓ 找到调试文件:
    dir /b "%USERPROFILE%\Desktop\ThoughtEcho_*"
    echo.
    echo 请查看桌面上的调试文件以获取详细信息
) else (
    echo ✗ 未找到调试文件
)

echo.
echo 测试完成。按任意键退出...
pause >nul
