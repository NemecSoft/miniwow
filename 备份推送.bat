@echo off
title MiniWoW Git 备份推送
cd /d %~dp0

echo ============================================
echo   MiniWoW 项目备份推送到 GitHub
echo   仓库: https://github.com/NemecSoft/miniwow
echo ============================================
echo.

echo [1/3] 收集改动...
git add -A
git status --short
echo.

set MSG=
set /p MSG=请输入本次提交说明(直接回车=自动命名): 
if "%MSG%"=="" set MSG=手动备份 %date% %time%

echo.
echo [2/3] 提交...
git commit -m "%MSG%"
if %errorlevel% neq 0 echo (没有新改动，跳过提交)
echo.

echo [3/3] 推送到 GitHub...
git push origin master:main
if %errorlevel% neq 0 (
    echo.
    echo 推送失败！如果是第一次推送，会弹出 GitHub 登录窗口，
    echo 请完成登录后重新双击本文件即可。
    echo 也可以把标签一并推送: 会自动执行
    git push origin --tags
    pause
    exit /b 1
)

git push origin --tags 2>nul
echo.
echo ============================================
echo   推送完成！查看: https://github.com/NemecSoft/miniwow
echo ============================================
pause
