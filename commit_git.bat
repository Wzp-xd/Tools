@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ===== Git commit helper =====
REM Usage 1: double-click and type message
REM Usage 2: commit_git.bat "your message"

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git not found in PATH.
  pause
  exit /b 1
)

if "%~1"=="" (
  set /p MSG=Enter commit message: 
) else (
  set MSG=%~1
)

if "!MSG!"=="" (
  echo [ERROR] Commit message is empty.
  pause
  exit /b 1
)

echo.
echo [1/4] git add -A
git add -A
if errorlevel 1 goto :fail

echo [2/4] git commit -m "!MSG!"
git commit -m "!MSG!"
if errorlevel 1 goto :fail

echo [3/4] Detect current branch
for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set BRANCH=%%b
if "!BRANCH!"=="" (
  echo [ERROR] Failed to detect current branch.
  goto :fail
)

echo [4/4] git push origin !BRANCH!
git push origin !BRANCH!
if errorlevel 1 goto :fail

echo.
echo [OK] Commit and push completed on branch: !BRANCH!
pause
exit /b 0

:fail
echo.
echo [ERROR] Failed. Check logs above.
pause
exit /b 1
