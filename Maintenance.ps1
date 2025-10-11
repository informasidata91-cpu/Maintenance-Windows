# ==========================================================
#  Windows Maintenance Script
# ==========================================================

$LogFile = "$env:SystemDrive\MaintenanceLog.txt"
Start-Transcript -Path $LogFile -Append

Write-Output "=== MEMULAI PROSES MAINTENANCE WINDOWS (Admin Mode) ==="
Write-Output "PERINGATAN:"
Write-Output "Jangan menutup jendela PowerShell atau CMD ini!"
Write-Output "Sistem sedang menjalankan proses Maintenance Windows otomatis."
Write-Output "Menutup jendela ini dapat menyebabkan proses gagal atau sistem tidak stabil."

# Fungsi helper untuk menjalankan perintah sebagai admin dan hidden
function Run-AdminCommand {
    param([string]$Command)
    Start-Process powershell -ArgumentList "-Command $Command" -Verb RunAs -WindowStyle Hidden -Wait
}

# --- 1. System File Checker ---
Write-Output "[1/9] Menjalankan SFC..."
Run-AdminCommand "sfc /scannow | Out-Null"

# --- 2. DISM - CheckHealth ---
Write-Output "[2/9] Menjalankan DISM /CheckHealth..."
Run-AdminCommand "DISM /Online /Cleanup-Image /CheckHealth | Out-Null"

# --- 3. DISM - ScanHealth ---
Write-Output "[3/9] Menjalankan DISM /ScanHealth..."
Run-AdminCommand "DISM /Online /Cleanup-Image /ScanHealth | Out-Null"

# --- 4. DISM - RestoreHealth ---
Write-Output "[4/9] Menjalankan DISM /RestoreHealth..."
Run-AdminCommand "DISM /Online /Cleanup-Image /RestoreHealth | Out-Null"

# --- 5. Flush DNS ---
Write-Output "[5/9] Membersihkan cache DNS..."
Run-AdminCommand "ipconfig /flushdns | Out-Null"

# --- 6. Reset Winsock ---
Write-Output "[6/9] Mereset Winsock..."
Run-AdminCommand "netsh winsock reset | Out-Null"

# --- 7. Deep Disk Cleanup - Drive C ---
Write-Output "[7/9] Menjalankan Disk Cleanup untuk drive C ..."

# Jalankan Disk Cleanup dengan semua opsi pembersihan (SageSet 65535)
Run-AdminCommand "cmd /c cleanmgr /sageset:65535 & cleanmgr /sagerun:65535"

# Bersihkan folder sementara pengguna dan sistem
Run-AdminCommand "cmd /c del /q /f /s %TEMP%\*"
Run-AdminCommand "cmd /c del /q /f /s C:\Windows\Temp\*"

# Bersihkan cache Windows Update
Run-AdminCommand "cmd /c net stop wuauserv"
Run-AdminCommand "cmd /c net stop bits"
Run-AdminCommand "cmd /c del /q /f /s C:\Windows\SoftwareDistribution\Download\*"
Run-AdminCommand "cmd /c net start wuauserv"
Run-AdminCommand "cmd /c net start bits"

# Bersihkan Delivery Optimization cache
Run-AdminCommand "cmd /c del /q /f /s C:\Windows\SoftwareDistribution\DeliveryOptimization\*"

# Bersihkan log dan Prefetch
Run-AdminCommand "cmd /c del /q /f /s C:\Windows\Prefetch\*"
Run-AdminCommand "cmd /c del /q /f /s C:\Windows\Logs\CBS\*"
Run-AdminCommand "cmd /c del /q /f /s C:\Windows\Logs\DISM\*"

# Bersihkan recycle bin
Run-AdminCommand "PowerShell -Command ""Clear-RecycleBin -Force"""

# Hapus file upgrade lama (Windows.old)
if (Test-Path "C:\Windows.old") {
    Run-AdminCommand "cmd /c rmdir /s /q C:\Windows.old"
}

Write-Output "[OK] Disk Cleanup drive C selesai."

# --- 8. CHKDSK (hanya bila perlu) ---
Write-Output "[8/9] Memeriksa integritas drive C..."
$chkdskOutput = cmd /c "chkdsk C:"
if ($chkdskOutput -match "corrections" -or $chkdskOutput -match "bad sectors" -or $chkdskOutput -match "found problems") {
    Write-Output "CHKDSK mendeteksi masalah, menjadwalkan perbaikan saat restart..."
    Run-AdminCommand "echo Y|chkdsk C: /F /R | Out-Null"
} else {
    Write-Output "Drive C: sehat, tidak perlu perbaikan CHKDSK."
}

# --- 9. Tes RAM otomatis setelah restart ---
Write-Output "[9/9] Menjadwalkan Windows Memory Diagnostic..."
Run-AdminCommand "schtasks /Create /TN MemTest /SC ONSTART /TR mdsched.exe /F | Out-Null"

Write-Output "=== PROSES MAINTENANCE SELESAI ==="
Write-Output "Komputer akan restart dalam 30 detik..."
Stop-Transcript

# Restart otomatis
Start-Sleep -Seconds 5
shutdown.exe /r /t 30 /c "Maintenance Windows selesai. Komputer akan restart otomatis."







