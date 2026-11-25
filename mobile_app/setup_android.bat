@echo off
REM ==============================================================
REM  Smart System Timesheet - one-time Android setup (Windows)
REM  Generates the android/ folder for YOUR Flutter version, then
REM  applies the app manifest, launcher icons and network config.
REM ==============================================================
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Flutter is not on PATH. Install Flutter and reopen the terminal.
  exit /b 1
)

if not exist "android\app\build.gradle" if not exist "android\app\build.gradle.kts" (
  echo Generating android project...
  call flutter create --platforms=android --org com.smartsystem --project-name smart_system_timesheet .
  if errorlevel 1 exit /b 1
)

echo Applying manifest, icons and network security config...
xcopy /E /Y /I /Q "android_overrides\*" "android\" >nul
if errorlevel 1 exit /b 1

call flutter pub get
if errorlevel 1 exit /b 1

echo.
echo Done.
echo   Run on a phone/emulator :  flutter run
echo   Build the APK           :  flutter build apk --release
echo   APK output              :  build\app\outputs\flutter-apk\app-release.apk
