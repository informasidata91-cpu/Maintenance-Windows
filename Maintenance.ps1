##[Ps1 To Exe]
##
##Kd3HDZOFADWE8uO1
##Nc3NCtDXTlaDjoHW8T1n8XfjQ2ElesCVuLikwc+1/OWM
##Kd3HFJGZHWLWoLaVvnQnhQ==
##LM/RF4eFHHGZ7/K1
##K8rLFtDXTiW5
##OsHQCZGeTiiZ4tI=
##OcrLFtDXTiW5
##LM/BD5WYTiiZ4tI=
##McvWDJ+OTiiZ4tI=
##OMvOC56PFnzN8u+Vs1Q=
##M9jHFoeYB2Hc8u+Vs1Q=
##PdrWFpmIG2HcofKIo2QX
##OMfRFJyLFzWE8uO1
##KsfMAp/KUzWI0g==
##OsfOAYaPHGbQvbyVvnQlqxugEiZ7Dg==
##LNzNAIWJGmPcoKHc7Do3uAu8DDhlPovL2Q==
##LNzNAIWJGnvYv7eVvnRa5ELgVm0lb8uYvPaQzY+48P3/2w==
##M9zLA5mED3nfu77Q7TV64AuzAkUqZ8uPvLimyoK5se/0vkU=
##NcDWAYKED3nfu77Q7TV64AuzAkUqZ8uPvLimyoK5nw==
##OMvRB4KDHmHQvbyVvnRA7EXqTX84LuiasLizwY+98enp+xDNQJYdXU0X
##P8HPFJGEFzWE8tI=
##KNzDAJWHD2fS8u+VxzVj5AvHTG4kfMiaqr8lIEPc
##P8HSHYKDCX3N8u+VQf03txu8FygPb9Ga+Z+pwo6u8uv/sqc9i9RUaFh71jv1A0OpSrIAUOYQpscUUVNK
##LNzLEpGeC3fMu77Ro2k3hQ==
##L97HB5mLAnfMu77Ro2k3hQ==
##P8HPCZWEGmaZ7/L39j178Qv4S2lrXsqMvKSUzISw86SsnCzNQY8WExR/gj3sFxHyFvUbQf0Atp8SWhBlJvwN7aDdGvSgQaMek7ouJuaes9I=
##L8/UAdDXTlGDjpXc9zxi53fDQ2ElesCVuLikwcyL9uTotDLKdbcVQFpjkyf9Cki4F/cKUJU=
##Kc/BRM3KXxU=
##
##
##fd6a9f26a06ea3bc99616d4851b372ba
<#
Version: 2.0.0.0
#>
# ============ Header & Setup ============
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

# OS guard (opsional bisa Anda pertahankan seperti semula)
$os = Get-CimInstance Win32_OperatingSystem
$ver = [Version]$os.Version
if ($ver.Major -lt 10) { throw "Unsupported OS: $($os.Caption) $($os.Version)" }

# TLS normalize
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

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# ============ Logging & Status ============
function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Warn','Error','Success','Green','Yellow','Red','Cyan','Gray','DarkYellow','DarkCyan')]
        [string]$Level = 'Info'
    )
    $fg = switch ($Level) {
        'Info'       { 'Cyan' }
        'Warn'       { 'Yellow' }
        'Error'      { 'Red' }
        'Success'    { 'Green' }
        'Green'      { 'Green' }
        'Yellow'     { 'Yellow' }
        'Red'        { 'Red' }
        'Cyan'       { 'Cyan' }
        'Gray'       { 'Gray' }
        'DarkYellow' { 'DarkYellow' }
        'DarkCyan'   { 'DarkCyan' }
        default      { 'Gray' }
    }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] $Message" -ForegroundColor $fg
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

function Section($i,$t,$name){
  Write-Host ("`n[{0}/{1}] {2}" -f $i,$t,$name) -ForegroundColor Yellow
  Write-Host ('=' * (12 + $name.Length)) -ForegroundColor DarkGray
}

# ============ External invocation ============
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

# ===================== SFC =====================
function Run-SFC {
  Write-Status 'SFC /Scannow...' 'Info'

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
  $script:SfcOutFile = $outFile
  try {
    $stdout | Out-File -FilePath $outFile -Encoding UTF8 -Force
    if ($stderr) { $stderr | Out-File -FilePath $outFile -Append -Encoding UTF8 }
    Write-Status ("Log SFC -> " + $outFile) 'DarkCyan'
  } catch {}

  return $p.ExitCode
}

function Get-DismTailInfo {
    param([int]$TailChars = 400000)
    $log = Join-Path $env:WINDIR 'Logs\DISM\dism.log'
    if (-not (Test-Path -LiteralPath $log)) { return '[dism.log not found]' }
    try {
        $txt = Get-Content -LiteralPath $log -Raw -ErrorAction Stop
        if ($txt.Length -gt $TailChars) { $txt = $txt.Substring($txt.Length - $TailChars) }
        $lines = $txt -split "\r?\n"
        $keys = 'CheckHealth','ScanHealth','RestoreHealth','Error:','FAILED','successfully','reboot'
        $hit = $lines | Where-Object { $_ -match ($keys -join '|') } | Select-Object -Last 5
        if ($hit) { return ($hit -join "`r`n") } else { return '[no key lines in tail]' }
    } catch { return "[read dism.log failed] $($_.Exception.Message)" }
}

function Invoke-Dism-Step {
    param(
        [Parameter(Mandatory)][string]$Args,   # '/Online /Cleanup-Image /ScanHealth'
        [Parameter(Mandatory)][string]$Label
    )
    Write-Status "DISM $Label..." 'Info'
    $proc = Start-Process -FilePath 'dism.exe' -ArgumentList $Args -WindowStyle Hidden -Wait -PassThru
    $code = $proc.ExitCode
    $tail = Get-DismTailInfo
    if ($code -eq 0) {
        Write-Status "[$Label] OK (exit 0)" 'Green'
    } else {
        Write-Status "[$Label] ExitCode: $code" 'Yellow'
    }
    Write-Status ("Log DISM (tail):`n" + $tail) 'DarkCyan'
    return $code
}

function Run-DISM-3 {
    $t0 = Get-Date
    $e1 = Invoke-Dism-Step -Args '/Online /Cleanup-Image /CheckHealth'    -Label 'CheckHealth'
    $e2 = Invoke-Dism-Step -Args '/Online /Cleanup-Image /ScanHealth'     -Label 'ScanHealth'
    $e3 = Invoke-Dism-Step -Args '/Online /Cleanup-Image /RestoreHealth'  -Label 'RestoreHealth'
    $dur = (Get-Date) - $t0

    if ($e3 -eq 0) {
        Write-Status ("DISM selesai tanpa error. Durasi: {0:N1} menit" -f $dur.TotalMinutes) 'Green'
    } else {
        Write-Status ("DISM selesai dengan error (exit $e3). Lihat ringkasan log di atas. Durasi: {0:N1} menit" -f $dur.TotalMinutes) 'Yellow'
    }
}

# ============ Clear log CBS dan DISM ============
function Wait-ServiceStateLimited {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Running','Stopped')][string]$TargetState,
        [int]$MaxTries = 10,
        [int]$SleepMs = 1000
    )
    $tries = 0
    while ($tries -lt $MaxTries) {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -eq $TargetState) { return $true }
        $tries++
        Write-Status ("Waiting for service '{0}' to {1}... ({2}/{3})" -f $Name, $TargetState.ToLower(), $tries, $MaxTries) 'DarkYellow'
        Start-Sleep -Milliseconds $SleepMs
    }
    return $false
}

function Clear-CbsAndDismLogs {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Backup,
        [int]$TailKeepDays = 7
    )

    $cbsDir  = Join-Path $env:WINDIR 'Logs\CBS'
    $dismDir = Join-Path $env:WINDIR 'Logs\DISM'

    Write-Status 'Membersihkan CBS.log & DISM.log...' 'Info'

    # Hentikan layanan yang menulis ke log (minimal)
    foreach($svc in 'trustedinstaller','wuauserv'){
        try { Stop-Service $svc -Force -ErrorAction SilentlyContinue } catch {}
    }
	# Stop aman (jika tidak sibuk)
		try { Stop-Service TrustedInstaller -Force -ErrorAction SilentlyContinue } catch {}
		try { Stop-Service wuauserv        -Force -ErrorAction SilentlyContinue } catch {}
	# PATCH: batasi pesan menunggu stop maksimal 10 kali
    [void](Wait-ServiceStateLimited -Name 'TrustedInstaller' -TargetState 'Stopped' -MaxTries 10 -SleepMs 1000)
    [void](Wait-ServiceStateLimited -Name 'wuauserv'        -TargetState 'Stopped' -MaxTries 10 -SleepMs 1000)

    # Backup opsional
    if ($Backup) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $zipPath = Join-Path $env:TEMP "logs_backup_$stamp.zip"
        try {
            $files = @()
            if (Test-Path $cbsDir)  { $files += Get-ChildItem $cbsDir -File -ErrorAction SilentlyContinue }
            if (Test-Path $dismDir) { $files += Get-ChildItem $dismDir -File -ErrorAction SilentlyContinue }
            if ($files) { Compress-Archive -Path $files.FullName -DestinationPath $zipPath -Force }
            if (Test-Path $zipPath) { Write-Status "Backup log -> $zipPath" 'DarkCyan' }
        } catch {
            Write-Status "Gagal backup log: $($_.Exception.Message)" 'Warn'
        }
    }

    # Rotasi & bersihkan CBS
    try {
        if (Test-Path $cbsDir) {
            Get-ChildItem $cbsDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -in 'CBS.log','CBS.persist.log') {
                    try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch {}
                } else {
                    if ($_.LastWriteTime -lt (Get-Date).AddDays(-$TailKeepDays)) {
                        try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch {}
                    }
                }
            }
        }
    } catch {
        Write-Status "CBS cleanup gagal: $($_.Exception.Message)" 'Warn'
    }

    # Rotasi & bersihkan DISM
    try {
        if (Test-Path $dismDir) {
            Get-ChildItem $dismDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -in 'dism.log') {
                    try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch {}
                } else {
                    if ($_.LastWriteTime -lt (Get-Date).AddDays(-$TailKeepDays)) {
                        try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch {}
                    }
                }
            }
        }
    } catch {
        Write-Status "DISM cleanup gagal: $($_.Exception.Message)" 'Warn'
    }
	# Mulai kembali layanan
	try { Start-Service wuauserv        -ErrorAction SilentlyContinue } catch {}
	try { Start-Service TrustedInstaller -ErrorAction SilentlyContinue } catch {}
    
    # PATCH: batasi pesan menunggu start maksimal 10 kali
    [void](Wait-ServiceStateLimited -Name 'wuauserv'        -TargetState 'Running' -MaxTries 10 -SleepMs 1000)
    [void](Wait-ServiceStateLimited -Name 'TrustedInstaller' -TargetState 'Running' -MaxTries 10 -SleepMs 1000)

    Write-Status 'CBS.log & DISM.log dibersihkan.' 'Green'
}

# ============ Windows Update reset ============
function Reset-WindowsUpdate {
  Write-Status 'Reset Windows Update components...' 'Info'
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

# ============ Cleanup ============
function Run-Cleanup {
  Write-Status 'Cleanup temp dan komponen...' 'Info'
  $paths = @($env:TEMP, $env:TMP, "$env:WINDIR\Temp") | Where-Object { $_ -and (Test-Path $_) }
  foreach ($p in $paths) {
    try { Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  }
  Invoke-External dism.exe '/Online /Cleanup-Image /StartComponentCleanup'
  try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
}

function Extra-Cleanup {
  Write-Status 'Extra cleanup...' 'Info'
  $targets = @(
    "$env:WINDIR\SoftwareDistribution\Download",
    "$env:WINDIR\SoftwareDistribution\DeliveryOptimization",
    "$env:WINDIR\Logs\CBS",
    "$env:WINDIR\Logs\DISM",
    "$env:WINDIR\Prefetch"
  )
  foreach ($t in $targets) { if (Test-Path $t) { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue } }
  if (Test-Path 'C:\Windows.old') {
    Write-Status 'Hapus Windows.old (rollback tidak lagi tersedia)...' 'Warn'
    try {
      Remove-Item 'C:\Windows.old' -Recurse -Force -ErrorAction Stop
    } catch {
      Write-Status 'Fallback takeown/icacls Windows.old...' 'Warn'
      Invoke-External takeown.exe '/F C:\Windows.old /R /A /D Y'
      Invoke-External icacls.exe 'C:\Windows.old /grant administrators:F /T'
      Invoke-External cmd.exe '/c rmdir /s /q C:\Windows.old'
    }
  }
}

# ============ Network fixes ============
function Flush-DNS { Write-Status 'Flush DNS cache...' 'Info'; try { Clear-DnsClientCache -ErrorAction SilentlyContinue } catch {} }
function Reset-Winsock { Write-Status 'Winsock reset...' 'Info'; Invoke-External netsh.exe 'winsock reset' }

# ============ Storage optimization ============
function Optimize-Drives {
  Write-Status 'Analyze + Defrag/ReTrim...' 'Info'
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
      Write-Status ('Optimize gagal ' + $v.DriveLetter + ': ' + $_.Exception.Message) 'Warn'
    }
  }
}

# ============ CHKDSK ============
function Invoke-ChkdskOnlineAndSchedule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$Drive = $env:SystemDrive,
        [switch]$UseSpotFix,
        [switch]$Hidden
    )

    # Normalisasi drive
    $drv = ($Drive.TrimEnd('\')).TrimEnd(':')
    if ([string]::IsNullOrWhiteSpace($drv)) { throw "Drive tidak valid: '$Drive'" }

    Write-Status "CHKDSK online /scan pada $drv`: ..." 'Info'
    $winStyle = if ($Hidden) { 'Hidden' } else { 'Normal' }

    # Jalankan scan dan ambil ExitCode dari objek proses (deterministik)
    $proc = Start-Process -FilePath 'cmd.exe' `
             -ArgumentList "/c chkdsk $drv`: /scan & exit %ERRORLEVEL%" `
             -WindowStyle $winStyle `
             -Wait -PassThru
    $code = $proc.ExitCode

    switch ($code) {
        0 { Write-Status "Tidak ada error terdeteksi oleh /scan pada $drv`:." 'Green' }
        1 { Write-Status "Ada error dan telah diperbaiki secara online (jika memungkinkan) pada $drv`:." 'Warn' }
        2 { Write-Status "Perlu perbaikan offline (tanpa /f). Pertimbangkan penjadwalan." 'Warn' }
        3 { Write-Status "Volume memerlukan pemeriksaan/perbaikan offline atau pemeriksaan gagal." 'Warn' }
        default { Write-Status "Kode keluar CHKDSK tak dikenal: $code" 'Warn' }
    }

    $needSchedule = ($code -in 2,3)
    if ($needSchedule) {
        $modeLabel = if ($UseSpotFix) { '/spotfix' } else { '/F /R' }
        if ($PSCmdlet.ShouldProcess("$drv`:", "Schedule CHKDSK $modeLabel at next reboot")) {
            Write-Status "Menjadwalkan CHKDSK $modeLabel pada reboot..." 'Warn'
            $fixArgs = if ($UseSpotFix) { "/spotfix" } else { "/F /R" }

            # Jalankan penjadwalan dengan elevasi dan ambil ExitCode deterministik
            $proc2 = Start-Process -FilePath 'cmd.exe' `
                      -ArgumentList "/c echo Y | chkdsk $drv`: $fixArgs & exit %ERRORLEVEL%" `
                      -Verb RunAs `
                      -WindowStyle $winStyle `
                      -Wait -PassThru
            $scheduleExit = $proc2.ExitCode

            if ($scheduleExit -eq 0) {
                Write-Status "CHKDSK $modeLabel telah dijadwalkan. Simpan pekerjaan Anda dan lakukan restart untuk memulai pemeriksaan." 'Warn'
            } else {
                Write-Status "Penjadwalan CHKDSK mungkin gagal (exit code: $scheduleExit). Coba jalankan sebagai Administrator." 'Error'
            }
        }
    } else {
        Write-Status 'Tidak perlu penjadwalan CHKDSK.' 'Green'
    }
}

# ============ Memory diagnostic ============
function Invoke-MemoryDiagnostic {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [ValidateSet('Schedule','RunNow')]
        [string]$Mode = 'Schedule',
        [switch]$Hidden
    )

    Write-Status 'Jalankan Windows Memory Diagnostic...' 'Info'
    $Exe = Join-Path $env:WINDIR 'System32\mdsched.exe'
    if (-not (Test-Path -LiteralPath $Exe)) {
        Write-Error "Tidak menemukan $Exe. Pastikan komponen Windows Memory Diagnostic tersedia."
        return
    }

    $Arg = if ($Mode -eq 'RunNow') { '/r' } else { '/s' }
    $winStyle = if ($Hidden) { 'Hidden' } else { 'Normal' }

    try {
        $target = "Windows Memory Diagnostic ($Mode)"
        if ($PSCmdlet.ShouldProcess($target, "Start-Process $($Exe) $Arg as Administrator")) {
            Start-Process -FilePath $Exe -ArgumentList $Arg -Verb RunAs -WindowStyle $winStyle -ErrorAction Stop
            if ($Mode -eq 'Schedule') {
                Write-Status "Tes RAM dijadwalkan pada boot berikutnya. Cek Event Viewer > Windows Logs > System, Source: MemoryDiagnostics-Results." 'Info'
            } else {
                Write-Status "Tes RAM akan berjalan segera (butuh restart). Cek hasil di Event Viewer setelah boot." 'Warn'
            }
        }
    }
    catch {
        Write-Error "Gagal memulai Windows Memory Diagnostic: $($_.Exception.Message)"
    }
}

# ============ Restart helpers ============
function Schedule-AutoRestart {
  param(
    [int]$TimeoutSec = 30,
    [string]$Comment = 'Maintenance Windows selesai.'
  )
  Write-Status "Jadwalkan restart otomatis dalam $TimeoutSec detik..." 'Warn'
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

# ============ Eksekusi utama ============
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

function Ensure-Folder {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        try { New-Item -ItemType Directory -Force -Path $Path | Out-Null } catch {}
    }
    return $Path
}

function Get-FileTail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TailLines = 0,
        [int]$TailChars = 0
    )
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    if ($TailLines -gt 0) {
        return ((Get-Content -LiteralPath $Path -Tail $TailLines -ErrorAction Stop) -join "`r`n")
    } elseif ($TailChars -gt 0) {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ($text.Length -gt $TailChars) { return $text.Substring($text.Length - $TailChars) }
        return $text
    } else {
        return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
    }
}

function Test-SFCIndicatesCorruption {
  param([int]$TailLines = 4000)
  $cbsDir = Join-Path $env:WINDIR 'Logs\CBS'
  Ensure-Folder $cbsDir | Out-Null
  $candidates = @(
    Join-Path $cbsDir 'CBS.log'
    Join-Path $cbsDir 'CBS.persist.log'
  ) | Where-Object { Test-Path -LiteralPath $_ }
  if (-not $candidates) { return $false }
  foreach ($p in $candidates) {
    try {
      $tail = Get-FileTail -Path $p -TailLines $TailLines
      if ([string]::IsNullOrEmpty($tail)) { continue }
      if ($tail -match 'Windows Resource Protection found corrupt files') { return $true }
      if ($tail -match 'unable to fix') { return $true }
      if ($tail -match 'successfully repaired') { return $true }
      if ($tail -match '\[SR\].*(cannot|repair|corrupt|hash)') { return $true }
    } catch { continue }
  }
  return $false
}

  $tasks = @(
	@{ Name='SFC'; Action={ if (-not $SkipSFC) { $script:SfcExit = Run-SFC } }; Skip=$SkipSFC },
	@{ Name='DISM 3-step'; Action={
		  if (-not $SkipDISM) {
			  Write-Status 'DISM akan dijalankan.' 'Info'
			  Run-DISM-3
		  }
		}; Skip=$SkipDISM },
	@{ Name='Cleanup CBS/DISM logs'; Action={
			Clear-CbsAndDismLogs -Backup -TailKeepDays 7
		}; Skip=$false },
    @{ Name='Reset Windows Update'; Action={ if (-not $SkipWUReset) { Reset-WindowsUpdate } }; Skip=$SkipWUReset },
    @{ Name='Network Fix'; Action={ if (-not $SkipNetworkFix) { Flush-DNS; Reset-Winsock } }; Skip=$SkipNetworkFix },
    @{ Name='Disk Cleanup'; Action={ if (-not $SkipCleanup) { Run-Cleanup } }; Skip=$SkipCleanup },
    @{ Name='Extra Cleanup'; Action={ if (-not $SkipExtraCleanup) { Extra-Cleanup } }; Skip=$SkipExtraCleanup },
    @{ Name='Optimize Drives'; Action={ if (-not $SkipDefrag) { Optimize-Drives } }; Skip=$SkipDefrag },
    @{ Name='CHKDSK'; Action={ if (-not $SkipChkdsk) { Invoke-ChkdskOnlineAndSchedule } }; Skip=$SkipChkdsk },
    @{ Name='Memory Diagnostic'; Action={ if (-not $SkipMemoryDiag) { Invoke-MemoryDiagnostic } }; Skip=$SkipMemoryDiag }
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
        Write-Status ($t.Name + ' -> [FAILED] ' + $_.Exception.Message) 'Error'
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
        Write-Status 'Fallback: Restart-Computer -Force dalam 30 detik' 'Warn'
        Start-Sleep -Seconds 30
        Restart-Computer -Force
      }
    } else {
      Write-Host "`nSelesai. Restart otomatis dalam 30 detik." -ForegroundColor Yellow
      Write-Host 'Tekan [A] lalu Enter untuk membatalkan.'
      try {
        Schedule-AutoRestart -TimeoutSec 30 -Comment 'Maintenance Windows selesai.'
      } catch {
        Write-Status 'Gagal menjadwalkan via shutdown.exe, gunakan fallback.' 'Warn'
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
# MIIdhQYJKoZIhvcNAQcCoIIddjCCHXICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCrDaWF5TKkk4Yl
# It737doZjduyjTGp3DQWiT/gbG+sGaCCA14wggNaMIICQqADAgECAhBKXDr997nE
# lEV/LmcB/M7aMA0GCSqGSIb3DQEBCwUAMEUxCzAJBgNVBAYTAklEMRowGAYDVQQK
# DBFEYXRhIEluZm9ybWFzaeKEojEaMBgGA1UEAwwRRGF0YSBJbmZvcm1hc2nihKIw
# HhcNMjUxMDI0MTc1NTQzWhcNMjYxMDI0MTgxNTQzWjBFMQswCQYDVQQGEwJJRDEa
# MBgGA1UECgwRRGF0YSBJbmZvcm1hc2nihKIxGjAYBgNVBAMMEURhdGEgSW5mb3Jt
# YXNp4oSiMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5fkXu9YwJxGQ
# iQTT1aqTxHyoQBqAVN0I+sMwDIGdfU3Gw4GIgSiPFhaMEngvWPg4hhP5aRG01ckW
# V+Eny8TIA5HDI1PCrnJxyzBANu0I4LyXNHyr3YA1W65Y3keOThPRUh2HsZ3i8MfX
# OeBUUeXW30CVZISum9LajAMQYnO2KVDBEOIINiGTuDHWlFCFpB0CfI23SZilZMR5
# gvAcBB5oW1A6gA+MQbBmhuuLFb3fc9SWeWgV0OA3rMLmXqTdgnRY/v1VVzzzmdE6
# xHd2do0bzNF47aXFGxO2OHE0NlVZfeqOJZrl1J25YYPDInOK2tXDwK7s0eTh/kOS
# 7HhMtlQxtQIDAQABo0YwRDAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYB
# BQUHAwMwHQYDVR0OBBYEFNjvWw4GL634EOZ5WOhycVJS3FyiMA0GCSqGSIb3DQEB
# CwUAA4IBAQAZpts/ruWrZ0S+PzpTYxpfOiFHmIi1IYoXEp9/zFcC+UJEvwJL5mzy
# qNwci3hy+XByL9sisUlTdHyPiyKxJZqlfhl9bNaddCKD42agaXMn43+/JfELrGSh
# fKneeRhkOu6Y0cnjEjhLgFINtBwdveWiZm8DJXgYGbrs8S4D4E9D9MX4YvQ6w7Gh
# pSOElYreTMFc8SHtHx1gUEhX0dV8WbdJADeWkI4LQPfaMI53VvPclSjh7i7P/csl
# 6NiaWF9NI2JlwvMwYvPbXUweOROERXsw1oTpEMc5ztlCFb3OAhk5qm+OuXYwtOY7
# ctmseQ2f5Up9VcjnPp+FUsvbv2hhLOnQMYIZfTCCGXkCAQEwWTBFMQswCQYDVQQG
# EwJJRDEaMBgGA1UECgwRRGF0YSBJbmZvcm1hc2nihKIxGjAYBgNVBAMMEURhdGEg
# SW5mb3JtYXNp4oSiAhBKXDr997nElEV/LmcB/M7aMA0GCWCGSAFlAwQCAQUAoHww
# EAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEILPO/o1P
# gd7651J72Hx2NMEu1fRIgplMcWJT+Kfl3VtdMA0GCSqGSIb3DQEBAQUABIIBAD3C
# c4CZIWgf1j/RL8fbZUz9RAOeILO3PV10Qnd3rT7rwOkMSCKWO44JDoO6Mo21/t2E
# ulOteoEzaZQq7VhDxqorQbOu6RxmmbWGlbRuTc+XejFsQBYCBKCzZt/qJ2i/zPUe
# KE7BZJ38OPPR/n9MVp3K24eVnV6x0lp86zZ6xJY13+UtA5tT2mbLuro1ppM8wffq
# sTTnlLkwBPZkRj11cvu96w/ijTiLUWiYVjtGYCJAah5ayywX/pjEdIjuwP0N3YRU
# eeXsOtPj2r8Zn0l033XDirOEepn6dSqsChLTbdy7+rScwU1/9icxR/OCcdN7wpNs
# ONvC2kSH6DUAE8usSqyhghd3MIIXcwYKKwYBBAGCNwMDATGCF2MwghdfBgkqhkiG
# 9w0BBwKgghdQMIIXTAIBAzEPMA0GCWCGSAFlAwQCAQUAMHgGCyqGSIb3DQEJEAEE
# oGkEZzBlAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQghhIcqUL5TJG3
# Lp0CzIKk36MbKy7LH/ZJq7jjo7yvC84CEQCkScnCjaX37UsCqER2vdUIGA8yMDI1
# MTExMDEyMjQzMVqgghM6MIIG7TCCBNWgAwIBAgIQCoDvGEuN8QWC0cR2p5V0aDAN
# BgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQs
# IEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5n
# IFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAwMDAwMFoXDTM2MDkw
# MzIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MTswOQYDVQQDEzJEaWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBUaW1lc3RhbXAgUmVz
# cG9uZGVyIDIwMjUgMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANBG
# rC0Sxp7Q6q5gVrMrV7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx+wvA69HFTBdwbHwB
# SOeLpvPnZ8ZN+vo8dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvNZh6wW2R6kSu9RJt/
# 4QhguSssp3qome7MrxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlLnh00Cll8pjrUcCV3
# K3E0zz09ldQ//nBZZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmncOOMA3CoB/iUSROU
# INDT98oksouTMYFOnHoRh6+86Ltc5zjPKHW5KqCvpSduSwhwUmotuQhcg9tw2YD3
# w6ySSSu+3qU8DD+nigNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL4Q1OpbybpMe46Yce
# NA0LfNsnqcnpJeItK/DhKbPxTTuGoX7wJNdoRORVbPR1VVnDuSeHVZlc4seAO+6d
# 2sC26/PQPdP51ho1zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCyFG1roSrgHjSHlq8x
# ymLnjCbSLZ49kPmk8iyyizNDIXj//cOgrY7rlRyTlaCCfw7aSUROwnu7zER6EaJ+
# AliL7ojTdS5PWPsWeupWs7NpChUk555K096V1hE0yZIXe+giAwW00aHzrDchIc2b
# Qhpp0IoKRR7YufAkprxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGjggGVMIIBkTAMBgNV
# HRMBAf8EAjAAMB0GA1UdDgQWBBTkO/zyMe39/dfzkXFjGVBDz2GM6DAfBgNVHSME
# GDAWgBTvb1NK6eQGfHrK4pBW9i/USezLTjAOBgNVHQ8BAf8EBAMCB4AwFgYDVR0l
# AQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGFMCQGCCsGAQUFBzAB
# hhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wXQYIKwYBBQUHMAKGUWh0dHA6Ly9j
# YWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGlu
# Z1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBp
# bmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIw
# CwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3xHCcEua5gQezRCESe
# Y0ByIfjk9iJP2zWLpQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh8/YmRDfxT7C0k8FU
# FqNh+tshgb4O6Lgjg8K8elC4+oWCqnU/ML9lFfim8/9yJmZSe2F8AQ/UdKFOtj7Y
# MTmqPO9mzskgiC3QYIUP2S3HQvHG1FDu+WUqW4daIqToXFE/JQ/EABgfZXLWU0zi
# TN6R3ygQBHMUBaB5bdrPbF6MRYs03h4obEMnxYOX8VBRKe1uNnzQVTeLni2nHkX/
# QqvXnNb+YkDFkxUGtMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq8/gVutDojBIFeRlq
# AcuEVT0cKsb+zJNEsuEB7O7/cuvTQasnM9AWcIQfVjnzrvwiCZ85EE8LUkqRhoS3
# Y50OHgaY7T/lwd6UArb+BOVAkg2oOvol/DJgddJ35XTxfUlQ+8Hggt8l2Yv7roan
# cJIFcbojBcxlRcGG0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1R9xJgKf47CdxVRd/
# ndUlQ05oxYy2zRWVFjF7mcr4C34Mj3ocCVccAvlKV9jEnstrniLvUxxVZE/rptb7
# IRE2lskKPIJgbaP5t2nGj/ULLi49xTcBZU8atufk+EMF/cWuiC7POGT75qaL6vdC
# vHlshtjdNXOCIUjsarfNZzCCBrQwggScoAMCAQICEA3HrFcF/yGZLkBDIgw6SYYw
# DQYJKoZIhvcNAQELBQAwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0
# IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNl
# cnQgVHJ1c3RlZCBSb290IEc0MB4XDTI1MDUwNzAwMDAwMFoXDTM4MDExNDIzNTk1
# OVowaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYD
# VQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNI
# QTI1NiAyMDI1IENBMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALR4
# MdMKmEFyvjxGwBysddujRmh0tFEXnU2tjQ2UtZmWgyxU7UNqEY81FzJsQqr5G7A6
# c+Gh/qm8Xi4aPCOo2N8S9SLrC6Kbltqn7SWCWgzbNfiR+2fkHUiljNOqnIVD/gG3
# SYDEAd4dg2dDGpeZGKe+42DFUF0mR/vtLa4+gKPsYfwEu7EEbkC9+0F2w4QJLVST
# EG8yAR2CQWIM1iI5PHg62IVwxKSpO0XaF9DPfNBKS7Zazch8NF5vp7eaZ2CVNxpq
# umzTCNSOxm+SAWSuIr21Qomb+zzQWKhxKTVVgtmUPAW35xUUFREmDrMxSNlr/NsJ
# yUXzdtFUUt4aS4CEeIY8y9IaaGBpPNXKFifinT7zL2gdFpBP9qh8SdLnEut/Gcal
# NeJQ55IuwnKCgs+nrpuQNfVmUB5KlCX3ZA4x5HHKS+rqBvKWxdCyQEEGcbLe1b8A
# w4wJkhU1JrPsFfxW1gaou30yZ46t4Y9F20HHfIY4/6vHespYMQmUiote8ladjS/n
# J0+k6MvqzfpzPDOy5y6gqztiT96Fv/9bH7mQyogxG9QEPHrPV6/7umw052AkyiLA
# 6tQbZl1KhBtTasySkuJDpsZGKdlsjg4u70EwgWbVRSX1Wd4+zoFpp4Ra+MlKM2ba
# oD6x0VR4RjSpWM8o5a6D8bpfm4CLKczsG7ZrIGNTAgMBAAGjggFdMIIBWTASBgNV
# HRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBTvb1NK6eQGfHrK4pBW9i/USezLTjAf
# BgNVHSMEGDAWgBTs1+OC0nFdZEzfLmc/57qYrhwPTzAOBgNVHQ8BAf8EBAMCAYYw
# EwYDVR0lBAwwCgYIKwYBBQUHAwgwdwYIKwYBBQUHAQEEazBpMCQGCCsGAQUFBzAB
# hhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKGNWh0dHA6Ly9j
# YWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3J0MEMG
# A1UdHwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dFRydXN0ZWRSb290RzQuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG
# /WwHATANBgkqhkiG9w0BAQsFAAOCAgEAF877FoAc/gc9EXZxML2+C8i1NKZ/zdCH
# xYgaMH9Pw5tcBnPw6O6FTGNpoV2V4wzSUGvI9NAzaoQk97frPBtIj+ZLzdp+yXdh
# OP4hCFATuNT+ReOPK0mCefSG+tXqGpYZ3essBS3q8nL2UwM+NMvEuBd/2vmdYxDC
# vwzJv2sRUoKEfJ+nN57mQfQXwcAEGCvRR2qKtntujB71WPYAgwPyWLKu6RnaID/B
# 0ba2H3LUiwDRAXx1Neq9ydOal95CHfmTnM4I+ZI2rVQfjXQA1WSjjf4J2a7jLzWG
# NqNX+DF0SQzHU0pTi4dBwp9nEC8EAqoxW6q17r0z0noDjs6+BFo+z7bKSBwZXTRN
# ivYuve3L2oiKNqetRHdqfMTCW/NmKLJ9M+MtucVGyOxiDf06VXxyKkOirv6o02Oo
# XN4bFzK0vlNMsvhlqgF2puE6FndlENSmE+9JGYxOGLS/D284NHNboDGcmWXfwXRy
# 4kbu4QFhOm0xJuF2EZAOk5eCkhSxZON3rGlHqhpB/8MluDezooIs8CVnrpHMiD2w
# L40mm53+/j7tFaxYKIqL0Q4ssd8xHZnIn/7GELH3IdvG2XlM9q7WP/UwgOkw/HQt
# yRN62JK4S1C8uw3PdBunvAZapsiI5YKdvlarEvf8EA+8hcpSM9LHJmyrxaFtoza2
# zNaQ9k+5t1wwggWNMIIEdaADAgECAhAOmxiO+dAt5+/bUOIIQBhaMA0GCSqGSIb3
# DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3Vy
# ZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBaFw0zMTExMDkyMzU5NTlaMGIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBH
# NDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAL/mkHNo3rvkXUo8MCIw
# aTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/zG6Q4FutWxpdtHauyefLK
# EdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZanMylNEQRBAu34LzB4Tm
# dDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7sWxq868nPzaw0QF+xembu
# d8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL2pNe3I6PgNq2kZhAkHnD
# eMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1
# XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3JFxGj2T3wWmIdph2PVld
# QnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3cAORFJYm2mkQZK37AlLTS
# YW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqxYxhElRp2Yn72gLD76GSm
# M9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0viastkF13nqsX40/ybzT
# QRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+dIPyhHsXAj6Kx
# fgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIBNjAPBgNVHRMBAf8EBTADAQH/
# MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwPTzAfBgNVHSMEGDAWgBRF66Kv
# 9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYBBQUHAQEEbTBr
# MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUH
# MAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJ
# RFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNl
# cnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDARBgNVHSAECjAIMAYG
# BFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0NcVec4X6CjdBs9thbX979XB72a
# rKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnovLbc47/T/gLn4offyct4kvFID
# yE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cGAxN3J0TU53/o
# Wajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9HNj0d1pcVIxv
# 76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPFmCLBsln1VWvPJ6tsds5vIy30
# fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQxggN8MIID
# eAIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFB
# MD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5
# NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEFgtHEdqeVdGgwDQYJYIZIAWUDBAIB
# BQCggdEwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEP
# Fw0yNTExMTAxMjI0MzFaMCsGCyqGSIb3DQEJEAIMMRwwGjAYMBYEFN1iMKyGCi0w
# a9o4sWh5UjAH+0F+MC8GCSqGSIb3DQEJBDEiBCBpn9Gnj0UDb2nG76vjhIdaPXXO
# xWQ7BbvgUZw8bLdpAjA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCBKoD+iLNdchMVc
# k4+CjmdrnK7Ksz/jbSaaozTxRhEKMzANBgkqhkiG9w0BAQEFAASCAgBc7VDQFT9p
# lKGCQ7+28WQMoqGcjX5It5ZT09E3PsBhE98yG8UvWl1tZ+C2QCuNDpn2ffb4+KCu
# RQUqxQyymiIJZAjET7hfIIY8boL6nIaF84l0XUNkMompIFp4PYwYclOV8UBk1wAQ
# ozdciKTvTSSGwlVjhGFXgzMTjip9N6HQcHDwzH4+qvMMtpsWqltySxqSxaytJA43
# NXKvR3u0jU2pCajKCSyEemjcv2lFS5PnMEY68NCRe0tnTrSuG6GbEpWXnznzDFiD
# avzHvIntImNhJu7/l7fgLRFIuXSdVBZ2ug700dOdKy3g/u0NIbbOmOmd3GIcKWgs
# HK0eiqC47bSYCTc9JA/LRHf4dp5QtDDQy3V/fNSREJu8yAdsQzujVx1avXaJdbof
# 4mF7DrNZxYc32dD4yuzdFoftwwXkPS0C9tcS+jZJPWnonlF4Oh6I8GxhAyt0JNo4
# lv028rd4fQEAwXTyfF+/KjvzpR8WzuKtvFric1R5TrRX/eMU/YasW7AbPWETFBS/
# NTfFTXbhwF9mBG4o8h1jJATMBpp6nIXy/x3D923VuhGG/n2FB0w/giBfRuBCUCsT
# OV/vhNYQB2sRyckZl7UaZBhg+QVZiLK9zuL5ud4Luoxizui/eV+ZDnkxd+YDgXv5
# SA8nKgHrIS8CdZBqfVAjAIXVemuotesu8A==
# SIG # End signature block
