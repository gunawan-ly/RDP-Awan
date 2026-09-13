<#
.SYNOPSIS
  Entry-point utama: Tailscale + native Windows RDP + Windows App. PRD Fase 13.
  Idempotent, fail-fast dengan exit code. Jalankan sebagai Administrator.

.DESCRIPTION
  12 langkah PRD:
   1. Check Administrator
   2. Check Windows edition
   3. Check Tailscale (install/auth diarahkan, tidak hardcode secret)
   4. Install Tailscale hanya jika -InstallTailscale dan installer tersedia/URL resmi
   5. Pastikan Tailscale service berjalan
   6. Pastikan Tailscale authenticated (tailscale ip -4 harus ada)
   7. Enable RDP (via Enable-RdpHost.ps1)
   8. Enable NLA (bagian dari Enable-RdpHost.ps1)
   9. Configure firewall Tailscale-only (via Set-RdpFirewallTailscale.ps1)
  10. Check TermService
  11. Obtain Tailscale IP (via Get-TailscaleIp.ps1)
  12. Print final connection information

  Secret (TAILSCALE_AUTHKEY) TIDAK boleh di-hardcode: baca dari
  $env:TAILSCALE_AUTHKEY atau parameter -AuthKey (mis. dari GitHub Secrets).

.PARAMETER RdpPort
  Default 3389 / $env:RDP_PORT.

.PARAMETER TailscaleHostname
  Hostname untuk "tailscale up --hostname=". Default: hostname komputer.

.PARAMETER AuthKey
  Opsional. Jika kosong, dipakai $env:TAILSCALE_AUTHKEY. Tidak pernah dicetak ke log.

.PARAMETER InstallTailscale
  Jika diberikan, script akan mengunduh installer resmi Tailscale bila tailscale.exe
  tidak ditemukan. Default: tidak install otomatis (hanya instruksi).

.PARAMETER InstallerUrl
  URL installer resmi. Default https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup_rdp_tailscale.ps1
  $env:TAILSCALE_AUTHKEY='tskey-...' ; powershell -ExecutionPolicy Bypass -File .\setup_rdp_tailscale.ps1 -InstallTailscale
#>
[CmdletBinding()]
param(
    [int]$RdpPort = 0,
    [string]$TailscaleHostname = '',
    [string]$AuthKey = '',
    [switch]$InstallTailscale,
    [string]$InstallerUrl = 'https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Get-RdpPort {
    param([int]$Override)
    if ($Override -gt 0) { return $Override }
    if ($env:RDP_PORT) {
        $parsed = 0
        if ([int]::TryParse($env:RDP_PORT, [ref]$parsed) -and $parsed -gt 0 -and $parsed -le 65535) {
            return $parsed
        }
    }
    return 3389
}

function Find-TailscaleExe {
    $fromPath = (Get-Command 'tailscale.exe' -ErrorAction SilentlyContinue)
    if ($fromPath) { return $fromPath.Source }
    foreach ($c in @('C:\Program Files\Tailscale\tailscale.exe', 'C:\Program Files (x86)\Tailscale\tailscale.exe')) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Invoke-SubScript {
    param([string]$Name, [string]$Args)
    $full = Join-Path $ScriptDir $Name
    if (-not (Test-Path $full)) {
        Write-Error "ERROR: Modul tidak ditemukan: $Name (exit 50)"
        exit 50
    }
    Write-Output "----> $Name $Args"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$full`" $Args"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEnd()
    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($out) { Write-Output $out }
    if ($err) { Write-Warning $err }
    return $proc.ExitCode
}

# --- 1. Admin ---
if (-not (Test-IsAdmin)) {
    Write-Error 'ERROR [1/12]: Harus Run as Administrator. (exit 10)'
    exit 10
}
Write-Output '[1/12] Administrator: OK.'

# --- 2. Edition (cek cepat; cek detail ada di Enable-RdpHost.ps1) ---
$caption = ''
try { $caption = (Get-CimInstance Win32_OperatingSystem).Caption } catch {}
Write-Output "[2/12] Windows edition: $caption"
if ($caption -and ($caption.ToLowerInvariant() -match 'home|starter|single language')) {
    Write-Error ("ERROR [2/12]: Edisi '{0}' tidak mendukung RDP host. Gunakan Pro/Enterprise/Education/Server. (exit 12)" -f $caption)
    exit 12
}

# --- 3/4. Tailscale check (+ optional install) ---
$Port = Get-RdpPort -Override $RdpPort
$tsExe = Find-TailscaleExe
if (-not $tsExe) {
    if ($InstallTailscale) {
        Write-Output '[3/12] Tailscale tidak ditemukan — mengunduh installer resmi...'
        $tmp = Join-Path $env:TEMP 'tailscale-setup-latest.exe'
        try {
            Invoke-WebRequest -Uri $InstallerUrl -OutFile $tmp -UseBasicParsing
            Start-Process -FilePath $tmp -ArgumentList '/quiet' -Wait
            Start-Sleep -Seconds 10
        } catch {
            Write-Error "ERROR [3/12]: Gagal install Tailscale: $($_.Exception.Message) (exit 42)"
            exit 42
        }
        $tsExe = Find-TailscaleExe
        if (-not $tsExe) {
            Write-Error 'ERROR [3/12]: Tailscale tetap tidak ditemukan setelah install. (exit 42)'
            exit 42
        }
    } else {
        Write-Error 'ERROR [3/12]: Tailscale tidak terinstall. Install dari https://tailscale.com/download atau jalankan ulang dengan -InstallTailscale. (exit 40)'
        exit 40
    }
}
Write-Output "[3/12] Tailscale: found ($tsExe)."

# --- 5. Service ---
try {
    $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        Write-Output '[5/12] Service Tailscale: starting...'
        Start-Service -Name 'Tailscale' -ErrorAction Stop
        Start-Sleep -Seconds 3
    }
    Write-Output '[5/12] Tailscale service: OK (service resmi, tanpa custom persistence).'
} catch {
    Write-Warning "[5/12] Tidak dapat memastikan service Tailscale: $($_.Exception.Message) (lanjut, akan terlihat di langkah 6)."
}

# --- 6. Authenticated? ---
$key = $AuthKey
if (-not $key) { $key = $env:TAILSCALE_AUTHKEY }
$existingIp = ''
try { $existingIp = (& $tsExe ip -4 2>$null | Where-Object { $_ -match '^100\.' } | Select-Object -First 1) } catch {}
if (-not $existingIp -and $key) {
    Write-Output '[6/12] Tailscale belum connected — mencoba "tailscale up" dengan auth key dari env/parameter...'
    $hn = $TailscaleHostname
    if (-not $hn) { $hn = $env:COMPUTERNAME }
    try {
        # Jangan echo key ke log.
        & $tsExe up --authkey=$key --hostname="$hn" 2>&1 | ForEach-Object { $_ -replace [regex]::Escape($key), '(redacted)' } | Write-Output
        Start-Sleep -Seconds 3
        $existingIp = (& $tsExe ip -4 2>$null | Where-Object { $_ -match '^100\.' } | Select-Object -First 1)
    } catch {
        Write-Error 'ERROR [6/12]: "tailscale up" gagal. Periksa auth key / tailnet policy. Key TIDAK dicetak ke log. (exit 43)'
        exit 43
    }
}
if (-not $existingIp) {
    Write-Error 'ERROR [6/12]: Tailscale belum authenticated/connected (tidak ada 100.x.x.x). Jika butuh aksi user: jalankan "tailscale up" manual lalu ulangi setup. Berhenti di sini sesuai PRD. (exit 41)'
    exit 41
}
Write-Output "[6/12] Tailscale authenticated: OK ($existingIp)."

# --- 7/8. RDP + NLA ---
$code = Invoke-SubScript -Name 'Enable-RdpHost.ps1' -Args "-RdpPort $Port"
if ($code -ne 0) {
    Write-Error "ERROR [7/12]: Enable-RdpHost.ps1 gagal (exit $code). Setup dibatalkan."
    exit $code
}
Write-Output '[7/12] RDP host + NLA: OK.'

# --- 9. Firewall ---
$code = Invoke-SubScript -Name 'Set-RdpFirewallTailscale.ps1' -Args "-RdpPort $Port"
if ($code -ne 0) {
    Write-Error "ERROR [9/12]: Set-RdpFirewallTailscale.ps1 gagal (exit $code). RDP TIDAK dibiarkan setengah aman."
    exit $code
}
Write-Output '[9/12] Firewall Tailscale-only: OK.'

# --- 10. TermService double-check ---
try {
    $t = Get-Service -Name 'TermService' -ErrorAction Stop
    if ($t.Status -ne 'Running') {
        Write-Error 'ERROR [10/12]: TermService tidak Running setelah setup. (exit 20)'
        exit 20
    }
    Write-Output '[10/12] TermService: Running.'
} catch {
    Write-Error "ERROR [10/12]: TermService tidak ditemukan/gagal: $($_.Exception.Message) (exit 20)"
    exit 20
}

# --- 11/12. IP + final info ---
$code = Invoke-SubScript -Name 'Get-TailscaleIp.ps1' -Args "-RdpPort $Port"
if ($code -ne 0) {
    Write-Error "ERROR [11/12]: Get-TailscaleIp.ps1 gagal (exit $code)."
    exit $code
}
Write-Output '[12/12] DONE. Hubungkan via Windows App ke IP/MagicDNS di atas memakai akun Windows PC target.'
exit 0
