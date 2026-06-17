@echo off
REM check_env.bat — detect Python + install missing deps (Windows)

REM Detect system python
where python3 >nul 2>&1 && (set PY=python3& goto :found)
where python >nul 2>&1 && (set PY=python& goto :found)

echo X Python not found. Install Python 3.10+ first.
exit /b 1

:found
echo Python: %PY%
%PY% "%~dp0check_env.py"
