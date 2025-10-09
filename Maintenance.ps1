# ==========================================================
#  Windows Maintenance Script - Silent Automated Mode (3-Step DISM)
# ==========================================================

$LogFile = "$env:SystemDrive\MaintenanceLog.txt"
Start-Transcript -Path $LogFile -Append

Write-Output "=== MEMULAI PROSES MAINTENANCE WINDOWS ==="
Write-Output "Log file: $LogFile"
Write-Output "Tanggal: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "-------------------------------------------"

# --- 1. System File Checker ---
Write-Output "[1/8] Menjalankan System File Checker..."
sfc /scannow | Out-Null

# --- 2. DISM - CheckHealth ---
Write-Output "[2/8] Menjalankan DISM /CheckHealth..."
DISM /Online /Cleanup-Image /CheckHealth | Out-Null

# --- 3. DISM - ScanHealth ---
Write-Output "[3/8] Menjalankan DISM /ScanHealth..."
DISM /Online /Cleanup-Image /ScanHealth | Out-Null

# --- 4. DISM - RestoreHealth ---
Write-Output "[4/8] Menjalankan DISM /RestoreHealth..."
DISM /Online /Cleanup-Image /RestoreHealth | Out-Null

# --- 5. Flush DNS ---
Write-Output "[5/8] Membersihkan cache DNS..."
ipconfig /flushdns | Out-Null

# --- 6. Reset Winsock ---
Write-Output "[6/8] Mereset Winsock..."
netsh winsock reset | Out-Null

# --- 7. CHKDSK (jalankan hanya bila perlu) ---
Write-Output "[7/8] Memeriksa integritas drive C..."
$chkdskOutput = cmd /c "chkdsk C:"
if ($chkdskOutput -match "corrections" -or $chkdskOutput -match "bad sectors" -or $chkdskOutput -match "found problems") {
    Write-Output "CHKDSK mendeteksi masalah, menjadwalkan perbaikan saat restart..."
    cmd /c "echo Y|chkdsk C: /F /R" | Out-Null
} else {
    Write-Output "Drive C: sehat, tidak perlu perbaikan CHKDSK."
}

# --- 8. Tes RAM otomatis setelah restart ---
Write-Output "[8/8] Menjadwalkan Memory Diagnostic..."
schtasks /Create /TN MemTest /SC ONSTART /TR mdsched.exe /F | Out-Null

# --- Selesai ---
Write-Output "-------------------------------------------"
Write-Output "=== PROSES MAINTENANCE SELESAI ==="
Write-Output "Komputer akan restart dalam 30 detik..."
Stop-Transcript

shutdown /r /t 30 /c "Maintenance Windows selesai. Komputer akan restart otomatis."
