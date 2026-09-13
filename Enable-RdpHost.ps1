<#
.SYNOPSIS
  Enable native Windows Remote Desktop host (RDP + NLA + TermService).
  PRD Fase 4. Idempotent. Tidak menyentuh Defender, user, password, atau persistence.

.DESCRIPTION
  - Cek Administrator.
  - Cek edisi Windows (peringatan jelas jika Home/single-language yang tidak mendukung RDP host).
  - Enable RDP via fDenyTSConnections=0.
  - Enable NLA via UserAuthentication=1.
  - Pastikan TermService Start=auto dan Running.
  - Hormati custom port via -RdpPort / env RDP_PORT (default 3389, PRD Fase 16).
  - Tidak membuka firewall di sini (lihat Set-RdpFirewallTailscale.ps1).
  - Tidak menonaktifkan security feature apapun.

.PARAMETER RdpPort
  TCP port RDP. Default 3389. Bisa juga via $env:RDP_PORT.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Enable-RdpHost.ps1
  powershell -ExecutionPolicy Bypass -File .\Enable-RdpHost.ps1 -RdpPort 3389
#>
[CmdletBinding()]
param(
    [int]$RdpPort = 0
)

$ErrorActionPreference = 'Stop'

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
        Write-Warning "env RDP_PORT='$env:RDP_PORT' tidak valid, pakai 3389."
    }
    return 3389
}

function Get-WindowsEdition {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return @{
            Caption = $os.Caption
            OperatingSystemSKU = $os.OperatingSystemSKU
        }
    } catch {
        return @{ Caption = 'Unknown'; OperatingSystemSKU = -1 }
    }
}

# SKU yang TIDAK mendukung RDP host (daftar utama, bukan exhaustive):
# 0=Ultimate? justru support. Yang tidak support: Home Basic(2), Home Premium(3),
# Starter(11), Home Basic N, dll. Pendekatan aman: peringatkan jika Caption mengandung 'Home'/'Starter'.
function Test-EditionSupportsRdpHost {
    param([string]$Caption)
    if (-not $Caption) { return $true }
    $lower = $Caption.ToLowerInvariant()
    if ($lower -match 'home|starter|single language') {
        return $false
    }
    return $true
}

# --- Main ---
if (-not (Test-IsAdmin)) {
    Write-Error 'ERROR: Script harus dijalankan sebagai Administrator. Klik kanan PowerShell -> Run as Administrator. (exit 10)'
    exit 10
}

$Port = Get-RdpPort -Override $RdpPort
if ($Port -le 0 -or $Port -gt 65535) {
    Write-Error "ERROR: RDP port tidak valid: $Port. (exit 11)"
    exit 11
}

$edition = Get-WindowsEdition
Write-Output "Windows edition : $($edition.Caption)"
if (-not (Test-EditionSupportsRdpHost -Caption $edition.Caption)) {
    Write-Error ("ERROR: Edisi Windows '{0}' umumnya TIDAK mendukung Remote Desktop host. " -f $edition.Caption) +
        'Gunakan Windows Pro / Enterprise / Education / Server. Setup dibatalkan agar tidak memberi kesan sukses palsu. (exit 12)'
    exit 12
}

try {
    # 1. Enable Remote Desktop
    $tsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $cur = (Get-ItemProperty -Path $tsPath -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
    if ($cur -ne 0) {
        Set-ItemProperty -Path $tsPath -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force
        Write-Output 'RDP host: enabled (fDenyTSConnections=0).'
    } else {
        Write-Output 'RDP host: already enabled (idempotent, skip).'
    }

    # 2. Enable NLA — WAJIB tetap on (PRD melarang disable NLA)
    $rdpTcp = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    $nla = (Get-ItemProperty -Path $rdpTcp -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication
    if ($nla -ne 1) {
        Set-ItemProperty -Path $rdpTcp -Name 'UserAuthentication' -Value 1 -Type DWord -Force
        Write-Output 'NLA: enabled (UserAuthentication=1).'
    } else {
        Write-Output 'NLA: already enabled (idempotent, skip).'
    }

    # 3. Custom port hanya jika != 3389 (kompatibilitas enable_rdp_and_open_port.bat lama)
    if ($Port -ne 3389) {
        $curPort = (Get-ItemProperty -Path $rdpTcp -Name 'PortNumber' -ErrorAction SilentlyContinue).PortNumber
        if ($curPort -ne $Port) {
            Set-ItemProperty -Path $rdpTcp -Name 'PortNumber' -Value $Port -Type DWord -Force
            Write-Output "RDP port: changed to $Port (restart TermService diperlukan)."
        } else {
            Write-Output "RDP port: already $Port (idempotent, skip)."
        }
    } else {
        Write-Output 'RDP port: 3389/TCP (default, tidak diubah).'
    }

    # 4. TermService auto + running
    $svc = Get-Service -Name 'TermService' -ErrorAction Stop
    if ($svc.StartType -ne 'Automatic') {
        Set-Service -Name 'TermService' -StartupType Automatic -ErrorAction Stop
        Write-Output 'TermService: startup set to Automatic.'
    } else {
        Write-Output 'TermService: already Automatic (idempotent, skip).'
    }
    if ($svc.Status -ne 'Running') {
        Start-Service -Name 'TermService' -ErrorAction Stop
        Start-Sleep -Seconds 2
        $svc.Refresh()
        if ($svc.Status -ne 'Running') {
            Write-Error 'ERROR: TermService gagal start setelah dicoba. (exit 20)'
            exit 20
        }
        Write-Output 'TermService: started.'
    } else {
        Write-Output 'TermService: already Running (idempotent, skip).'
    }
} catch {
    Write-Error "ERROR: Gagal mengaktifkan RDP host: $($_.Exception.Message) (exit 21)"
    exit 21
}

Write-Output "OK: Windows RDP host aktif. Port=$Port NLA=Enabled TermService=Running."
exit 0
