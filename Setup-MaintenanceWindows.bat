@echo off
:: ==========================================================
:: Script: Setup-MaintenanceWindows.bat
:: Deskripsi:
:: - Mengunduh skrip PowerShell diagnostik dari GitHub
:: - Menjalankannya melalui PowerShell
:: - Membuat jadwal bulanan otomatis di Task Scheduler
:: ==========================================================

setlocal
set "SCRIPT_DIR=%~dp0"
set "TEMP_SCRIPT=%SCRIPT_DIR%Perintah-Diagnostik-Temp.ps1"
set "TASK_NAME=Maintenance-Windows-Bulanan"
set "GITHUB_URL=https://raw.githubusercontent.com/informasidata91-cpu/Maintenance-Windows/main/Perintah-Diagnostik-Windows.txt"

echo ==========================================================
echo [INFO] Menjalankan Setup Maintenance Windows
echo ==========================================================
echo.

:: === 1. Unduh file PowerShell dari GitHub ===
echo [INFO] Mengunduh perintah PowerShell terbaru dari GitHub...
powershell -Command "(New-Object Net.WebClient).DownloadFile('%GITHUB_URL%', '%TEMP_SCRIPT%')" 2>nul

if not exist "%TEMP_SCRIPT%" (
    echo [ERROR] Gagal mengunduh file dari GitHub.
    echo Pastikan koneksi internet aktif dan URL benar.
    pause
    exit /b
)
echo [OK] File PowerShell berhasil diunduh.
echo.

:: === 2. Jalankan PowerShell script ===
echo [INFO] Menjalankan perintah diagnostik (PowerShell)...
powershell -ExecutionPolicy Bypass -File "%TEMP_SCRIPT%"
echo.
echo [OK] Semua perintah PowerShell telah dijalankan.
echo.

:: === 3. Buat jadwal bulanan otomatis ===
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if %errorlevel%==0 (
    echo [INFO] Jadwal sudah ada. Tidak perlu membuat ulang.
    goto :DONE
)

echo [INFO] Membuat jadwal otomatis bulanan...
schtasks /Create /SC MONTHLY /D 1 /ST 09:00 /RL HIGHEST /TN "%TASK_NAME%" /TR "powershell -ExecutionPolicy Bypass -File \"%~f0\"" /F >nul

if %errorlevel%==0 (
    echo [OK] Jadwal berhasil dibuat: Setiap tanggal 1 pukul 09:00 pagi.
) else (
    echo [ERROR] Gagal membuat jadwal otomatis.
)

:DONE
echo.
echo ==========================================================
echo [SELESAI] Setup Maintenance Windows selesai dijalankan.
echo ==========================================================
pause
exit /b
