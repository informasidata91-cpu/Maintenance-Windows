# ==========================================================
#  Windows Maintenance Script
# ==========================================================

$LogFile = "$env:SystemDrive\MaintenanceLog.txt"
Start-Transcript -Path $LogFile -Append

Write-Output "=== MEMULAI PROSES MAINTENANCE WINDOWS (Admin Mode) ==="

# Fungsi helper untuk menjalankan perintah sebagai admin dan hidden
function Run-AdminCommand {
    param([string]$Command)
    Start-Process powershell -ArgumentList "-Command $Command" -Verb RunAs -WindowStyle Hidden -Wait
}

# --- 1. System File Checker ---
Write-Output "[1/8] Menjalankan SFC..."
Run-AdminCommand "sfc /scannow | Out-Null"

# --- 2. DISM - CheckHealth ---
Write-Output "[2/8] Menjalankan DISM /CheckHealth..."
Run-AdminCommand "DISM /Online /Cleanup-Image /CheckHealth | Out-Null"

# --- 3. DISM - ScanHealth ---
Write-Output "[3/8] Menjalankan DISM /ScanHealth..."
Run-AdminCommand "DISM /Online /Cleanup-Image /ScanHealth | Out-Null"

# --- 4. DISM - RestoreHealth ---
Write-Output "[4/8] Menjalankan DISM /RestoreHealth..."
Run-AdminCommand "DISM /Online /Cleanup-Image /RestoreHealth | Out-Null"

# --- 5. Flush DNS ---
Write-Output "[5/8] Membersihkan cache DNS..."
Run-AdminCommand "ipconfig /flushdns | Out-Null"

# --- 6. Reset Winsock ---
Write-Output "[6/8] Mereset Winsock..."
Run-AdminCommand "netsh winsock reset | Out-Null"

# --- 7. CHKDSK (hanya bila perlu) ---
Write-Output "[7/8] Memeriksa integritas drive C..."
$chkdskOutput = cmd /c "chkdsk C:"
if ($chkdskOutput -match "corrections" -or $chkdskOutput -match "bad sectors" -or $chkdskOutput -match "found problems") {
    Write-Output "CHKDSK mendeteksi masalah, menjadwalkan perbaikan saat restart..."
    Run-AdminCommand "echo Y|chkdsk C: /F /R | Out-Null"
} else {
    Write-Output "Drive C: sehat, tidak perlu perbaikan CHKDSK."
}

# --- 8. Tes RAM otomatis setelah restart ---
Write-Output "[8/8] Menjadwalkan Windows Memory Diagnostic..."
Run-AdminCommand "schtasks /Create /TN MemTest /SC ONSTART /TR mdsched.exe /F | Out-Null"

Write-Output "=== PROSES MAINTENANCE SELESAI ==="
Write-Output "Komputer akan restart dalam 30 detik..."
Stop-Transcript

# Restart otomatis
Start-Sleep -Seconds 5
shutdown.exe /r /t 30 /c "Maintenance Windows selesai. Komputer akan restart otomatis."
