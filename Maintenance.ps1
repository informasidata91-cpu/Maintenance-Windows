<#
Version: 2.2.0.1
Fokus: PS 5.1, logging kuat, SFC -> DISM -> CHKDSK online, reset Windows Update, optimasi HDD/SSD.
Perbaikan: SFC parsing output untuk memicu DISM saat ada korup (meski exit code 0); fallback cek CBS.log.
#>

[CmdletBinding()]
param(
  [switch]$Silent,
  [switch]$SkipDISM,
  [switch]$SkipSFC,
  [switch]$SkipWUReset,
  [switch]$SkipCleanup,
  [switch]$SkipDefrag,
  [switch]$SkipChkdsk,
  [switch]$SkipNetworkFix,
  [switch]$SkipMemoryDiag,
  [switch]$SkipExtraCleanup,
  [switch]$NoRestart,
  [switch]$ForceAutoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LogFile = 'C:\MaintenanceLog.txt'
$script:StartTime = Get-Date

# TLS
$OriginalProtocol = [Net.ServicePointManager]::SecurityProtocol
try {
  if ($PSVersionTable.PSVersion.Major -ge 7) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::SystemDefault
  } else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  }
} catch {}

function Ensure-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
      if ($kv.Value -eq $true) {
        $argList += "-$($kv.Key)"
      } else {
        $argList += "-$($kv.Key) `"$($kv.Value)`""
      }
    }
    $psi.Arguments = ($argList -join ' ')
    $psi.Verb = 'runas'
    [Diagnostics.Process]::Start($psi) | Out-Null
    exit
  }
}

function Write-Status($msg, $color='Gray') {
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$ts] $msg" -ForegroundColor $color
}

function New-Log {
  try {
    if (-not (Test-Path -LiteralPath $LogFile)) { New-Item -ItemType File -Path $LogFile -Force | Out-Null }
    Start-Transcript -Path $LogFile -Append | Out-Null
    Write-Status "Transcript -> $LogFile" 'DarkCyan'
  } catch {
    Write-Host ('Gagal memulai transcript: ' + $($_.Exception.Message)) -ForegroundColor Yellow
  }
}

function Stop-Log {
  try { Stop-Transcript | Out-Null } catch {}
  $d = (Get-Date) - $script:StartTime
  Write-Host ('Log: ' + $LogFile + ' (Durasi: ' + [Math]::Round($d.TotalMinutes,2) + ' menit)') -ForegroundColor Cyan
}

# Jalankan proses eksternal lewat cmd agar output tampil
function Invoke-External {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string]$Arguments = '',
    [int[]]$SuccessExitCodes = @(0),
    [int]$TimeoutSec = 0
  )
  Write-Host ('>> ' + $FilePath + ' ' + $Arguments) -ForegroundColor DarkGray
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'cmd.exe'
  $psi.Arguments = '/c "' + $FilePath + '" ' + $Arguments
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $false
  $psi.RedirectStandardError = $false
  $psi.CreateNoWindow = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  if ($TimeoutSec -gt 0) {
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
      try { $p.Kill() } catch {}
      throw ('Timeout menjalankan: ' + $FilePath + ' ' + $Arguments)
    }
  } else { $p.WaitForExit() }
  if ($SuccessExitCodes -notcontains $p.ExitCode) {
    throw ('ExitCode ' + $p.ExitCode + ': ' + $FilePath + ' ' + $Arguments)
  }
}

function Section($i,$t,$name){
  Write-Host ("`n[{0}/{1}] {2}" -f $i,$t,$name) -ForegroundColor Yellow
  Write-Host ('=' * (12 + $name.Length)) -ForegroundColor DarkGray
}

# ---- Integrity (SFC/DISM) ----
function Run-SFC {
  Write-Status 'SFC /Scannow...'
  # Tangkap output untuk deteksi korup meski exit code 0
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName  = 'cmd.exe'
  $psi.Arguments = '/c sfc.exe /scannow'
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()

  $outFile = Join-Path $env:TEMP ("sfc_out_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  try {
    $stdout | Out-File -FilePath $outFile -Encoding UTF8 -Force
    if ($stderr) { $stderr | Out-File -FilePath $outFile -Append -Encoding UTF8 }
    Write-Status ("Log SFC -> " + $outFile) 'DarkCyan'
  } catch {}

  $foundCorrupt = $false
  if ($stdout -match 'Windows Resource Protection found corrupt files') { $foundCorrupt = $true }
  if ($stdout -match 'unable to fix' -or $stdout -match 'successfully repaired') { $foundCorrupt = $true }

  # Kembalikan 1 jika ada indikasi korup (agar memicu DISM), selain itu pakai exit code asli
  if ($foundCorrupt) { return 1 } else { return $p.ExitCode }
}

function Run-DISM-3 {
  Write-Status 'DISM CheckHealth...'
  Invoke-External dism.exe '/Online /Cleanup-Image /CheckHealth'
  Write-Status 'DISM ScanHealth...'
  Invoke-External dism.exe '/Online /Cleanup-Image /ScanHealth'
  Write-Status 'DISM RestoreHealth...'
  Invoke-External dism.exe '/Online /Cleanup-Image /RestoreHealth'
}

# ---- Windows Update reset ----
function Reset-WindowsUpdate {
  Write-Status 'Reset Windows Update components...'
  $svcs = 'bits','wuauserv','cryptsvc','msiserver'
  foreach ($s in $svcs) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
  Start-Sleep 2
  $sd = Join-Path $env:windir 'SoftwareDistribution'
  $cr = Join-Path $env:windir 'System32\catroot2'
  $ts = Get-Date -f yyyyMMddHHmmss
  if (Test-Path $sd) { Rename-Item $sd "$sd.bak-$ts" -ErrorAction SilentlyContinue }
  if (Test-Path $cr) { Rename-Item $cr "$cr.bak-$ts" -ErrorAction SilentlyContinue }
  foreach ($s in $svcs) { Start-Service $s -ErrorAction SilentlyContinue }
}

# ---- Cleanup ----
function Run-Cleanup {
  Write-Status 'Cleanup temp dan komponen...'
  $paths = @($env:TEMP, $env:TMP, "$env:WINDIR\Temp") | Where-Object { $_ -and (Test-Path $_) }
  foreach ($p in $paths) {
    try { Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  }
  Invoke-External dism.exe '/Online /Cleanup-Image /StartComponentCleanup'
  try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
}

function Extra-Cleanup {
  Write-Status 'Extra cleanup...'
  $targets = @(
    "$env:WINDIR\SoftwareDistribution\Download",
    "$env:WINDIR\SoftwareDistribution\DeliveryOptimization",
    "$env:WINDIR\Logs\CBS",
    "$env:WINDIR\Logs\DISM",
    "$env:WINDIR\Prefetch"
  )
  foreach ($t in $targets) { if (Test-Path $t) { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue } }
  if (Test-Path 'C:\Windows.old') {
    Write-Status 'Hapus Windows.old (rollback tidak lagi tersedia)...'
    try {
      Remove-Item 'C:\Windows.old' -Recurse -Force -ErrorAction Stop
    } catch {
      Write-Status 'Fallback takeown/icacls Windows.old...'
      Invoke-External takeown.exe '/F C:\Windows.old /R /A /D Y'
      Invoke-External icacls.exe 'C:\Windows.old /grant administrators:F /T'
      Invoke-External cmd.exe '/c rmdir /s /q C:\Windows.old'
    }
  }
}

# ---- Network fixes ----
function Flush-DNS { Write-Status 'Flush DNS cache...'; try { Clear-DnsClientCache -ErrorAction SilentlyContinue } catch {} }
function Reset-Winsock { Write-Status 'Winsock reset...'; Invoke-External netsh.exe 'winsock reset' }

# ---- Storage optimization ----
function Optimize-Drives {
  Write-Status 'Analyze + Defrag/ReTrim...'
  $vols = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
  foreach ($v in $vols) {
    try {
      Optimize-Volume -DriveLetter $v.DriveLetter -Analyze -ErrorAction SilentlyContinue 4> $null
      $dl = $v.DriveLetter
      $isSSD = $false
      try {
        $pd = Get-Partition -DriveLetter $dl | Get-Disk | Get-PhysicalDisk -ErrorAction Stop
        $isSSD = ($pd.MediaType -eq 'SSD')
      } catch {}
      if ($isSSD) {
        Optimize-Volume -DriveLetter $dl -ReTrim -ErrorAction SilentlyContinue 4> $null
      } else {
        Optimize-Volume -DriveLetter $dl -Defrag -ErrorAction SilentlyContinue 4> $null
      }
    } catch {
      Write-Status ('Optimize gagal ' + $v.DriveLetter + ': ' + $_.Exception.Message) 'DarkYellow'
    }
  }
}

# ---- CHKDSK ----
function Chkdsk-Online-And-Schedule {
  Write-Status 'CHKDSK online /scan...'
  $drv = $env:SystemDrive.TrimEnd(':')
  $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c chkdsk $drv`: /scan" -Wait -PassThru
  $needRepair = $LASTEXITCODE -ne 0
  if ($needRepair) {
    Write-Status 'Menjadwalkan CHKDSK /F /R pada reboot...'
    Start-Process -FilePath 'cmd.exe' -ArgumentList "/c echo Y | chkdsk $drv`: /F /R" -Verb RunAs -Wait
  } else {
    Write-Status 'Tidak perlu penjadwalan CHKDSK.' 'Green'
  }
}

# ---- Memory diagnostic ----
function Schedule-MemoryDiagnostic {
  Write-Status 'Jadwalkan Windows Memory Diagnostic...'
  Start-Process "$env:WINDIR\System32\mdsched.exe" '/s' -Verb RunAs
}

# ---- Auto Restart (diperkuat) ----
function Schedule-AutoRestart {
  param(
    [int]$TimeoutSec = 30,
    [string]$Comment = 'Maintenance Windows selesai.'
  )
  Write-Status "Jadwalkan restart otomatis dalam $TimeoutSec detik..."
  $args = "/r /t $TimeoutSec /c `"$Comment`""
  $p = Start-Process -FilePath "$env:WINDIR\System32\shutdown.exe" -ArgumentList $args -Verb RunAs -PassThru -WindowStyle Hidden
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "Gagal menjadwalkan restart (exit $($p.ExitCode))." }
}

function Abort-Restart {
  try {
    $p = Start-Process -FilePath "$env:WINDIR\System32\shutdown.exe" -ArgumentList '/a' -PassThru -WindowStyle Hidden
    $p.WaitForExit()
    Write-Host 'Restart dibatalkan.' -ForegroundColor Cyan
  } catch {
    Write-Host 'Gagal membatalkan restart.' -ForegroundColor Yellow
  }
}

# ===== Eksekusi =====
try {
  Ensure-Admin
  New-Log

  if (-not $Silent) {
    Write-Host "==============================================="
    Write-Host "  PEMBERITAHUAN MAINTENANCE WINDOWS"
    Write-Host "==============================================="
    Write-Host "Sistem akan restart otomatis setelah selesai." -ForegroundColor Yellow
    Write-Host "Jangan mematikan komputer sebelum proses maintenance selesai." -ForegroundColor Yellow
    Write-Host 'Proses bisa memakan waktu - simpan pekerjaan Anda.' -ForegroundColor Yellow
    Write-Host "-----------------------------------------------"
    Write-Host "`n*** MEMULAI MAINTENANCE WINDOWS ***" -ForegroundColor Cyan
    Start-Sleep 2
  }

  $tasks = @(
    @{ Name='SFC'; Action={ if (-not $SkipSFC) { $script:SfcExit = Run-SFC } }; Skip=$SkipSFC },
    @{ Name='DISM 3-step (kondisional)'; Action={
        if (-not $SkipDISM) {
          $needDism = ($script:SfcExit -ne 0)
          # Fallback: baca CBS.log bila SFC exit 0 tapi ada indikasi korup
          try {
            $cbsPath = "$env:WINDIR\Logs\CBS\CBS.log"
            if (Test-Path $cbsPath) {
              $cbs = Get-Content $cbsPath -ErrorAction SilentlyContinue -Tail 2000 -Raw
              if ($cbs -match 'Windows Resource Protection found corrupt files') { $needDism = $true }
              if ($cbs -match 'unable to fix') { $needDism = $true }
            }
          } catch {}
          if ($needDism) { Run-DISM-3 } else { Write-Status 'SFC OK; DISM dilewati (tidak diperlukan)' }
        }
      }; Skip=$SkipDISM },
    @{ Name='Reset Windows Update'; Action={ if (-not $SkipWUReset) { Reset-WindowsUpdate } }; Skip=$SkipWUReset },
    @{ Name='Network Fix'; Action={ if (-not $SkipNetworkFix) { Flush-DNS; Reset-Winsock } }; Skip=$SkipNetworkFix },
    @{ Name='Disk Cleanup'; Action={ if (-not $SkipCleanup) { Run-Cleanup } }; Skip=$SkipCleanup },
    @{ Name='Extra Cleanup'; Action={ if (-not $SkipExtraCleanup) { Extra-Cleanup } }; Skip=$SkipExtraCleanup },
    @{ Name='Optimize Drives'; Action={ if (-not $SkipDefrag) { Optimize-Drives } }; Skip=$SkipDefrag },
    @{ Name='CHKDSK'; Action={ if (-not $SkipChkdsk) { Chkdsk-Online-And-Schedule } }; Skip=$SkipChkdsk },
    @{ Name='Memory Diagnostic'; Action={ if (-not $SkipMemoryDiag) { Schedule-MemoryDiagnostic } }; Skip=$SkipMemoryDiag }
  )

  $TotalSteps = $tasks.Count
  $executed = [System.Collections.ArrayList]::new()
  $i = 0
  foreach ($t in $tasks) {
    $i++
    Section $i $TotalSteps $t.Name
    if ($t.Skip) {
      Write-Status ($t.Name + ' -> [SKIPPED]') 'DarkYellow'
      [void]$executed.Add("[$i/$TotalSteps] $($t.Name) -> SKIPPED")
    } else {
      try {
        & $t.Action
        Write-Status ($t.Name + ' -> [OK]') 'Green'
        [void]$executed.Add("[$i/$TotalSteps] $($t.Name) -> OK")
      } catch {
        Write-Status ($t.Name + ' -> [FAILED] ' + $_.Exception.Message) 'Red'
        [void]$executed.Add("[$i/$TotalSteps] $($t.Name) -> FAILED: $($_.Exception.Message)")
      }
    }
  }

  Write-Host "`n===== RINGKASAN MAINTENANCE =====" -ForegroundColor Cyan
  $executed | ForEach-Object { Write-Host $_ }

  if (-not $NoRestart) {
    if ($ForceAutoRestart -or $Silent) {
      try {
        Schedule-AutoRestart -TimeoutSec 30 -Comment 'Maintenance Windows selesai.'
        Start-Sleep -Seconds 2
      } catch {
        Write-Status 'Fallback: Restart-Computer -Force dalam 30 detik' 'DarkYellow'
        Start-Sleep -Seconds 30
        Restart-Computer -Force
      }
    } else {
      Write-Host "`nSelesai. Restart otomatis dalam 30 detik." -ForegroundColor Yellow
      Write-Host 'Tekan [A] lalu Enter untuk membatalkan.'
      try {
        Schedule-AutoRestart -TimeoutSec 30 -Comment 'Maintenance Windows selesai.'
      } catch {
        Write-Status 'Gagal menjadwalkan via shutdown.exe, gunakan fallback.' 'DarkYellow'
        Start-Sleep -Seconds 30
        Restart-Computer -Force
        throw
      }
      $start = Get-Date
      while ((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds -lt 30) {
        if ($Host.UI.RawUI.KeyAvailable) {
          $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
          if ($key.Character -in @('A','a')) {
            Abort-Restart
            break
          }
        }
        Start-Sleep -Milliseconds 200
      }
    }
  } else {
    Write-Status 'NoRestart aktif - tidak restart otomatis.' 'DarkYellow'
  }

  exit 0
}
catch {
  Write-Host ('Kesalahan fatal: ' + $($_.Exception.Message)) -ForegroundColor Red
  exit 1
}
finally {
  try { [Net.ServicePointManager]::SecurityProtocol = $OriginalProtocol } catch {}
  Stop-Log
}

# SIG # Begin signature block
# MIIdAAYJKoZIhvcNAQcCoIIc8TCCHO0CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBHUowRJxLmjd6x
# LFKIFJ880gCir3y0c7FIpcAzf+qAI6CCAwYwggMCMIIB6qADAgECAhAZrzFe5u2H
# lEcnVFobyhgaMA0GCSqGSIb3DQEBCwUAMBkxFzAVBgNVBAMMDkRhdGEgSW5mb3Jt
# YXNpMB4XDTI1MTAxNDE1MDY0NFoXDTI2MTAxNDE1MjY0NFowGTEXMBUGA1UEAwwO
# RGF0YSBJbmZvcm1hc2kwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDK
# KOimn/rO8oquB3IYQEvPkdJ5mk5sM5BQhPXAsw+MsNN2eS59bRCOTpPNU7QYGH0i
# nV4zl4J8Q2nn8PYBHpfB7qnpF6o0R2FmKvtyXm5h5BL960t32AdVKvTaNTdVePem
# fFctHs0ccSG+/prTtFRpSDCgGc/hwTfgyVZXqycYHowKMtpW+nCXbm+WR2ccvzPF
# IgMMBBNidBqKLG+tx8XpuTpqefWd3JNSLsG7kbqEMoW4Eb0LBoWHTtTANrCJIrkG
# 8i6uaByVFNql8FLDEkXOZkETIEMQrS2JmV1bNI0npFLGmtNc1aTB+4DXjLF8H9By
# 2SgfKggcJyUCIzUFkqrVAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUE
# DDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUwj6ufSrvSADxwHh0EWvwUdQSFlowDQYJ
# KoZIhvcNAQELBQADggEBAAzmRmgUe2ADXtL1u9xHH7lQ2dJRWq/7g3mJ2BVFXxRB
# mWtxs7f2J70Amk0bvPfCLYCX61niK2h/27jyx361NDfe9QEh2ql6wgYzZZDat299
# U1X9pIQn3YRZ5Vz2ckM08Y1eS4E0W3Jfbvbbp9x4q8UWJA9J6CfYAhYPnAQXyhU3
# cHiwk7EUlvsa/nYZBdLobz3nUfXgtIPd42Wgnh3DFrwjLNlwtQgg28jkBdj/3PIH
# P0ZUE45RFsm0fX9WL8hA5WEBN4KPrwKu6sjcjpsFPiQIVoRTkG2u6wGMJVwXKdCu
# g1ej/ogMNB8uWwOhfu6Wd8gDLFKi8n/r5UJPJ41VqGQxghlQMIIZTAIBATAtMBkx
# FzAVBgNVBAMMDkRhdGEgSW5mb3JtYXNpAhAZrzFe5u2HlEcnVFobyhgaMA0GCWCG
# SAFlAwQCAQUAoHwwEAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcN
# AQkEMSIEIPHOWGA/B53rb/thY5lfGMniTWJcWddxnBoopCQaJGFZMA0GCSqGSIb3
# DQEBAQUABIIBAAyt8tjvj6q/RCqGdZ/4KeaIiuUomkIA/B05hmwF0sWdjSLUPKEe
# P9s3ea8MJL/o/hQ+cRgbmDcq7UcL6DbuVDiYmF5fvqMuPURIV4BQfHHQpt5j+bdm
# W1c9/mUXiVms2CfjLO5YNUZNd/D01ciFBPRTtDlVgKojvYw0tUsbvjW/J4gDmTx0
# Mz7bJpVtiondQxoYfaptmRWes7eujQbpdh2i1q59IIH8gnPFIaQoiu8nOIyTWR/C
# GA4LjBYqzoSqK+NePl2ND4CWjS/CWZjQbJjPzBjDmEn7MDcRIQYqPewZyC+fyCnz
# BiAtop0TQbC7Qhv0tT14aXYJl12XHrrJTOehghd2MIIXcgYKKwYBBAGCNwMDATGC
# F2IwghdeBgkqhkiG9w0BBwKgghdPMIIXSwIBAzEPMA0GCWCGSAFlAwQCAQUAMHcG
# CyqGSIb3DQEJEAEEoGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEF
# AAQgJ/71DaBoSJfQde1idARcisp9oiYyOJzwPos4z+ZseNICEHx4nbPDliELBwKd
# CsL+xrYYDzIwMjUxMDI0MTIyNzMyWqCCEzowggbtMIIE1aADAgECAhAKgO8YS43x
# BYLRxHanlXRoMA0GCSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQK
# Ew5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBU
# aW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwHhcNMjUwNjA0MDAw
# MDAwWhcNMzYwOTAzMjM1OTU5WjBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGln
# aUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFNIQTI1NiBSU0E0MDk2IFRp
# bWVzdGFtcCBSZXNwb25kZXIgMjAyNSAxMIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
# MIICCgKCAgEA0EasLRLGntDqrmBWsytXum9R/4ZwCgHfyjfMGUIwYzKomd8U1nH7
# C8Dr0cVMF3BsfAFI54um8+dnxk36+jx0Tb+k+87H9WPxNyFPJIDZHhAqlUPt281m
# HrBbZHqRK71Em3/hCGC5KyyneqiZ7syvFXJ9A72wzHpkBaMUNg7MOLxI6E9RaUue
# HTQKWXymOtRwJXcrcTTPPT2V1D/+cFllESviH8YjoPFvZSjKs3SKO1QNUdFd2adw
# 44wDcKgH+JRJE5Qg0NP3yiSyi5MxgU6cehGHr7zou1znOM8odbkqoK+lJ25LCHBS
# ai25CFyD23DZgPfDrJJJK77epTwMP6eKA0kWa3osAe8fcpK40uhktzUd/Yk0xUvh
# DU6lvJukx7jphx40DQt82yepyekl4i0r8OEps/FNO4ahfvAk12hE5FVs9HVVWcO5
# J4dVmVzix4A77p3awLbr89A90/nWGjXMGn7FQhmSlIUDy9Z2hSgctaepZTd0ILIU
# bWuhKuAeNIeWrzHKYueMJtItnj2Q+aTyLLKLM0MheP/9w6CtjuuVHJOVoIJ/DtpJ
# RE7Ce7vMRHoRon4CWIvuiNN1Lk9Y+xZ66lazs2kKFSTnnkrT3pXWETTJkhd76CID
# BbTRofOsNyEhzZtCGmnQigpFHti58CSmvEyJcAlDVcKacJ+A9/z7eacCAwEAAaOC
# AZUwggGRMAwGA1UdEwEB/wQCMAAwHQYDVR0OBBYEFOQ7/PIx7f391/ORcWMZUEPP
# YYzoMB8GA1UdIwQYMBaAFO9vU0rp5AZ8esrikFb2L9RJ7MtOMA4GA1UdDwEB/wQE
# AwIHgDAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDCBlQYIKwYBBQUHAQEEgYgwgYUw
# JAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBdBggrBgEFBQcw
# AoZRaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0
# VGltZVN0YW1waW5nUlNBNDA5NlNIQTI1NjIwMjVDQTEuY3J0MF8GA1UdHwRYMFYw
# VKBSoFCGTmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRH
# NFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNybDAgBgNVHSAEGTAX
# MAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBAGUqrfEc
# JwS5rmBB7NEIRJ5jQHIh+OT2Ik/bNYulCrVvhREafBYF0RkP2AGr181o2YWPoSHz
# 9iZEN/FPsLSTwVQWo2H62yGBvg7ouCODwrx6ULj6hYKqdT8wv2UV+Kbz/3ImZlJ7
# YXwBD9R0oU62PtgxOao872bOySCILdBghQ/ZLcdC8cbUUO75ZSpbh1oipOhcUT8l
# D8QAGB9lctZTTOJM3pHfKBAEcxQFoHlt2s9sXoxFizTeHihsQyfFg5fxUFEp7W42
# fNBVN4ueLaceRf9Cq9ec1v5iQMWTFQa0xNqItH3CPFTG7aEQJmmrJTV3Qhtfparz
# +BW60OiMEgV5GWoBy4RVPRwqxv7Mk0Sy4QHs7v9y69NBqycz0BZwhB9WOfOu/CIJ
# nzkQTwtSSpGGhLdjnQ4eBpjtP+XB3pQCtv4E5UCSDag6+iX8MmB10nfldPF9SVD7
# weCC3yXZi/uuhqdwkgVxuiMFzGVFwYbQsiGnoa9F5AaAyBjFBtXVLcKtapnMG3VH
# 3EmAp/jsJ3FVF3+d1SVDTmjFjLbNFZUWMXuZyvgLfgyPehwJVxwC+UpX2MSey2ue
# Iu9THFVkT+um1vshETaWyQo8gmBto/m3acaP9QsuLj3FNwFlTxq25+T4QwX9xa6I
# Ls84ZPvmpovq90K8eWyG2N01c4IhSOxqt81nMIIGtDCCBJygAwIBAgIQDcesVwX/
# IZkuQEMiDDpJhjANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYD
# VQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcN
# MzgwMTE0MjM1OTU5WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQs
# IEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5n
# IFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
# MIICCgKCAgEAtHgx0wqYQXK+PEbAHKx126NGaHS0URedTa2NDZS1mZaDLFTtQ2oR
# jzUXMmxCqvkbsDpz4aH+qbxeLho8I6jY3xL1IusLopuW2qftJYJaDNs1+JH7Z+Qd
# SKWM06qchUP+AbdJgMQB3h2DZ0Mal5kYp77jYMVQXSZH++0trj6Ao+xh/AS7sQRu
# QL37QXbDhAktVJMQbzIBHYJBYgzWIjk8eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0
# Xm+nt5pnYJU3Gmq6bNMI1I7Gb5IBZK4ivbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQV
# ESYOszFI2Wv82wnJRfN20VRS3hpLgIR4hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2
# qHxJ0ucS638ZxqU14lDnki7CcoKCz6eum5A19WZQHkqUJfdkDjHkccpL6uoG8pbF
# 0LJAQQZxst7VvwDDjAmSFTUms+wV/FbWBqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgx
# CZSKi17yVp2NL+cnT6Toy+rN+nM8M7LnLqCrO2JP3oW//1sfuZDKiDEb1AQ8es9X
# r/u6bDTnYCTKIsDq1BtmXUqEG1NqzJKS4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7O
# gWmnhFr4yUozZtqgPrHRVHhGNKlYzyjlroPxul+bgIspzOwbtmsgY1MCAwEAAaOC
# AV0wggFZMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFO9vU0rp5AZ8esri
# kFb2L9RJ7MtOMB8GA1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1Ud
# DwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkw
# JAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcw
# AoY1aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJv
# b3RHNC5jcnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwB
# BAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEw
# vb4LyLU0pn/N0IfFiBowf0/Dm1wGc/Do7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8
# G0iP5kvN2n7Jd2E4/iEIUBO41P5F448rSYJ59Ib61eoalhnd6ywFLerycvZTAz40
# y8S4F3/a+Z1jEMK/DMm/axFSgoR8n6c3nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCD
# A/JYsq7pGdogP8HRtrYfctSLANEBfHU16r3J05qX3kId+ZOczgj5kjatVB+NdADV
# ZKON/gnZruMvNYY2o1f4MXRJDMdTSlOLh0HCn2cQLwQCqjFbqrXuvTPSegOOzr4E
# Wj7PtspIHBldNE2K9i697cvaiIo2p61Ed2p8xMJb82Yosn0z4y25xUbI7GIN/TpV
# fHIqQ6Ku/qjTY6hc3hsXMrS+U0yy+GWqAXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0
# c1ugMZyZZd/BdHLiRu7hAWE6bTEm4XYRkA6Tl4KSFLFk43esaUeqGkH/wyW4N7Oi
# gizwJWeukcyIPbAvjSabnf7+Pu0VrFgoiovRDiyx3zEdmcif/sYQsfch28bZeUz2
# rtY/9TCA6TD8dC3JE3rYkrhLULy7Dc90G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz
# 0scmbKvFoW2jNrbM1pD2T7m3XDCCBY0wggR1oAMCAQICEA6bGI750C3n79tQ4ghA
# GFowDQYJKoZIhvcNAQEMBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lD
# ZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGln
# aUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTIyMDgwMTAwMDAwMFoXDTMxMTEw
# OTIzNTk1OVowYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZ
# MBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1
# c3RlZCBSb290IEc0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAv+aQ
# c2jeu+RdSjwwIjBpM+zCpyUuySE98orYWcLhKac9WKt2ms2uexuEDcQwH/MbpDgW
# 61bGl20dq7J58soR0uRf1gU8Ug9SH8aeFaV+vp+pVxZZVXKvaJNwwrK6dZlqczKU
# 0RBEEC7fgvMHhOZ0O21x4i0MG+4g1ckgHWMpLc7sXk7Ik/ghYZs06wXGXuxbGrzr
# yc/NrDRAX7F6Zu53yEioZldXn1RYjgwrt0+nMNlW7sp7XeOtyU9e5TXnMcvak17c
# jo+A2raRmECQecN4x7axxLVqGDgDEI3Y1DekLgV9iPWCPhCRcKtVgkEy19sEcypu
# kQF8IUzUvK4bA3VdeGbZOjFEmjNAvwjXWkmkwuapoGfdpCe8oU85tRFYF/ckXEaP
# ZPfBaYh2mHY9WV1CdoeJl2l6SPDgohIbZpp0yt5LHucOY67m1O+SkjqePdwA5EUl
# ibaaRBkrfsCUtNJhbesz2cXfSwQAzH0clcOP9yGyshG3u3/y1YxwLEFgqrFjGESV
# GnZifvaAsPvoZKYz0YkH4b235kOkGLimdwHhD5QMIR2yVCkliWzlDlJRR3S+Jqy2
# QXXeeqxfjT/JvNNBERJb5RBQ6zHFynIWIgnffEx1P2PsIV/EIFFrb7GrhotPwtZF
# X50g/KEexcCPorF+CiaZ9eRpL5gdLfXZqbId5RsCAwEAAaOCATowggE2MA8GA1Ud
# EwEB/wQFMAMBAf8wHQYDVR0OBBYEFOzX44LScV1kTN8uZz/nupiuHA9PMB8GA1Ud
# IwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA4GA1UdDwEB/wQEAwIBhjB5Bggr
# BgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNv
# bTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lD
# ZXJ0QXNzdXJlZElEUm9vdENBLmNydDBFBgNVHR8EPjA8MDqgOKA2hjRodHRwOi8v
# Y3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMBEG
# A1UdIAQKMAgwBgYEVR0gADANBgkqhkiG9w0BAQwFAAOCAQEAcKC/Q1xV5zhfoKN0
# Gz22Ftf3v1cHvZqsoYcs7IVeqRq7IviHGmlUIu2kiHdtvRoU9BNKei8ttzjv9P+A
# ufih9/Jy3iS8UgPITtAq3votVs/59PesMHqai7Je1M/RQ0SbQyHrlnKhSLSZy51P
# pwYDE3cnRNTnf+hZqPC/Lwum6fI0POz3A8eHqNJMQBk1RmppVLC4oVaO7KTVPeix
# 3P0c2PR3WlxUjG/voVA9/HYJaISfb8rbII01YBwCA8sgsKxYoA5AY8WYIsGyWfVV
# a88nq2x2zm8jLfR+cWojayL/ErhULSd+2DrZ8LaHlv1b0VysGMNNn3O3AamfV6pe
# KOK5lDGCA3wwggN4AgEBMH0waTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFt
# cGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMQIQCoDvGEuN8QWC0cR2p5V0aDAN
# BglghkgBZQMEAgEFAKCB0TAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJ
# KoZIhvcNAQkFMQ8XDTI1MTAyNDEyMjczMlowKwYLKoZIhvcNAQkQAgwxHDAaMBgw
# FgQU3WIwrIYKLTBr2jixaHlSMAf7QX4wLwYJKoZIhvcNAQkEMSIEIJMKpMyJ+fYo
# ddO5MPHJ3PKFwh8KNo8ijEwL8gPeciRMMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIE
# IEqgP6Is11yExVyTj4KOZ2ucrsqzP+NtJpqjNPFGEQozMA0GCSqGSIb3DQEBAQUA
# BIICABCz67bwEP+lYuuxUXZv/XJBbr6eahMTYKTvjbKmoGYC8+EgBehCxhZ0Qas7
# Nl2w/26W9bGk5uREHJmW7N4cnioSs9rJH9BSQnb4NXcoSILyfkl2W1LUWIFS40Ut
# BJ/ocGjvZIJ6cuk/idjxXm4qb5nhNme7uVXo+UM8D887MfVrtl0GrVd7Pz6w6p4b
# 7Nc32qKoA20i4JfiKdcJetHZjgpdCkn+dNJxCMo3OuF7JzjbcoVvlyZsYHtrs9kW
# cAIBvm++a4mV2KN08EA9WM5UtPY88toRFDoQ5NnYfc0ivk2VyCTCKrw3wJdUQC/6
# +yxFt2CmtlCgNWxLvfSaY63TmV+phDDnpNcD9bXNhZ9btwZcfYOkeGhBMiThm/zB
# PC5xkTa3V65cvTczrthpbXzHBoPHqivI7u/jTcaDcJKk/TxHTbqrt6qsiMmgbPy/
# FizslJG4rkLYlMc3vTdT/cgjqZMQ9SG5eSSIxtVjvzMk1VS8GSl+E2Yd52bfNVz9
# /M6Hc+dlAlnpaV8a27tvyYBGlsQ1lfzJqgzAKv6wsUSpxXuynELugAmkw2+G2zVu
# k2UGbo0djSe8iZubnXzIM6bHnwFWmEn0J+k4D8nksRNT6zGF0oNJ8DRQWjmZjm2D
# Urk+aaq7T7XBFsiB5qi88jlpXwzmpqV61aPnBJPyg288Ayel
# SIG # End signature block
