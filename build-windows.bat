@echo off
setlocal

set "PROJECT_DIR=%~dp0"
set "DEPENDENCIES_DIR=%PROJECT_DIR%..\dependencies"
set "LDC_DIR=%DEPENDENCIES_DIR%\ldc2-1.41.0-windows-x64\bin"
set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"

if not exist "%VCVARS%" (
  echo ERROR: Visual Studio environment script was not found:
  echo   %VCVARS%
  set "RESULT=1"
  goto :finish
)
if not exist "%LDC_DIR%\ldc2.exe" (
  echo ERROR: LDC was not found:
  echo   %LDC_DIR%\ldc2.exe
  set "RESULT=1"
  goto :finish
)
if not exist "%LDC_DIR%\dub.exe" (
  echo ERROR: DUB was not found:
  echo   %LDC_DIR%\dub.exe
  set "RESULT=1"
  goto :finish
)

call "%VCVARS%" >nul
if errorlevel 1 (
  set "RESULT=%ERRORLEVEL%"
  echo ERROR: Visual Studio environment setup failed.
  goto :finish
)

set "LOCALAPPDATA=%DEPENDENCIES_DIR%\localappdata"
set "APPDATA=%DEPENDENCIES_DIR%\appdata"

pushd "%PROJECT_DIR%"
"%LDC_DIR%\dub.exe" build -b release-debug --compiler="%LDC_DIR%\ldc2.exe" --cache=local -y -n
set "RESULT=%ERRORLEVEL%"
popd

if not "%RESULT%"=="0" (
  echo ERROR: Sac Engine build failed with exit code %RESULT%.
) else (
  echo Sac Engine build completed successfully.
)

:finish
echo.
echo Press any key to close this window.
pause >nul
exit /b %RESULT%
