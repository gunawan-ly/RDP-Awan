<#
.SYNOPSIS
  Konfigurasi Windows Firewall agar SSH hanya dapat diakses via Tailscale.
  Pasangan SSH dari Set-RdpFirewallTailscale.ps1. Idempotent.
  TIDAK PERNAH membuka 22 ke Internet.

.DESCRIPTION
  Masalah bawaan: instalasi OpenSSH Server (Windows Capability) membuat
  rule "OpenSSH-Server-In-TCP" yang mengizinkan TCP/22 dari SEMUA alamat
  (RemoteAddress Any). Rule itu HARUS dimatikan di setup tailnet-only.

  Strategi (sama seperti versi RDP, tidak bergantung nama adapter):
  - Nonaktifkan rule bawaan OpenSSH bila aktif dan tidak dibatasi.
  - Buat SATU rule idempotent:
      Name        : "Allow SSH from Tailscale only"
      Dir         : In, Action: Allow, Protocol: TCP, LocalPort: <SshPort>
      RemoteAddress: 100.64.0.0/10  (Carrier-Grade NAT range resmi
                     Tailscale, 100.x.x.x)
      Profile     : Any (pembatasan via RemoteAddress, sehingga interface
                    publik dengan IP non-100.64/10 tetap DITOLAK)
  - Windows Firewall service tetap aktif (tidak pernah di-disable).
  - Tidak membuat duplicate rule saat dijalankan berulang.
  - Verifikasi akhir: tidak boleh ada rule ALLOW lain untuk port SSH
    yang RemoteAddress-nya Any.

.PARAMETER SshPort
  Default 22, bisa via $env:SSH_PORT.

.PARAMETER RuleName
  Nama rule baru. Default "Allow SSH from Tailscale only".

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Set-SshFirewallTailscale.ps1
#>
[CmdletBinding()]
param(
    [int]$SshPort = 0,
    [string]$RuleName = 'Allow SSH from Tailscale only'
)

$ErrorActionPreference = 'Stop'

# Tailscale IPv4 resmi selalu di 100.64.0.0/10 (100.64.0.0 - 100.127.255.255).
$TailscaleCgnat = '100.64.0.0/10'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Get-SshPort {
    param([int]$Override)
    if ($Override -gt 0) { return $Override }
    if ($env:SSH_PORT) {
        $parsed = 0
        if ([int]::TryParse($env:SSH_PORT, [ref]$parsed) -and $parsed -gt 0 -and $parsed -le 65535) {
            return $parsed
        }
    }
    return 22
}

if (-not (Test-IsAdmin)) {
    Write-Error 'ERROR: Script harus dijalankan sebagai Administrator. (exit 10)'
    exit 10
}

$Port = Get-SshPort -Override $SshPort

# 1. Pastikan Windows Firewall service ada dan berjalan (jangan pernah disable).
try {
    $fw = Get-Service -Name 'MpsSvc' -ErrorAction Stop
    if ($fw.Status -ne 'Running') {
        Write-Output 'Windows Firewall (MpsSvc): mencoba start...'
        Start-Service -Name 'MpsSvc' -ErrorAction Stop
        Start-Sleep -Seconds 2
    }
    Write-Output 'Windows Firewall (MpsSvc): Running.'
} catch {
    Write-Error "ERROR: Windows Firewall service (MpsSvc) tidak tersedia/ gagal start: $($_.Exception.Message) (exit 30)"
    exit 30
}

# 2. Nonaktifkan rule bawaan OpenSSH yang terbuka ke Any.
#    Idempotent: tidak error jika rule tidak ada / sudah nonaktif.
foreach ($name in @('OpenSSH-Server-In-TCP')) {
    try {
        $hits = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
        foreach ($h in $hits) {
            $addr = (Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $h -ErrorAction SilentlyContinue).RemoteAddress
            if ($h.Enabled -eq 'True' -and (-not $addr -or $addr -contains 'Any')) {
                Disable-NetFirewallRule -Name $name -ErrorAction Stop
                Write-Output "Rule bawaan OpenSSH '$name' dinonaktifkan (sebelumnya ALLOW TCP/$Port dari ANY)."
            } else {
                Write-Output "Rule bawaan OpenSSH '$name': sudah nonaktif atau sudah dibatasi — dipertahankan."
            }
        }
    } catch {
        Write-Warning "Gagal audit rule bawaan '$name': $($_.Exception.Message)"
    }
}

# 3. Buat/pastikan rule Tailscale-only (idempotent).
try {
    $existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
    if ($existing) {
        # Verifikasi propertinya benar; perbaiki jika melenceng.
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $existing[0] -ErrorAction SilentlyContinue
        $addrFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $existing[0] -ErrorAction SilentlyContinue
        $needFix = $false
        if ($portFilter.Protocol -ne 'TCP' -or ($portFilter.LocalPort -notcontains "$Port")) { $needFix = $true }
        if (-not ($addrFilter.RemoteAddress -contains $TailscaleCgnat)) { $needFix = $true }
        if ($existing[0].Enabled -ne 'True' -or $existing[0].Direction -ne 'Inbound' -or $existing[0].Action -ne 'Allow') { $needFix = $true }
        if ($needFix) {
            Remove-NetFirewallRule -DisplayName $RuleName -ErrorAction Stop
            Write-Output "Rule '$RuleName' ada tapi tidak sesuai — dibuat ulang."
            $existing = $null
        } else {
            Write-Output "Rule '$RuleName': sudah benar (idempotent, skip). TCP/$Port dari $TailscaleCgnat."
        }
    }
    if (-not $existing) {
        New-NetFirewallRule -DisplayName $RuleName `
            -Description 'SSH hanya via Tailscale tailnet (100.64.0.0/10). Dibuat oleh Set-SshFirewallTailscale.ps1. Jangan ubah ke RemoteAddress Any.' `
            -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port `
            -RemoteAddress $TailscaleCgnat `
            -Profile Any -Enabled True -ErrorAction Stop | Out-Null
        Write-Output "Rule '$RuleName' dibuat: ALLOW TCP/$Port FROM $TailscaleCgnat."
    }
} catch {
    Write-Error "ERROR: Gagal membuat firewall rule: $($_.Exception.Message) (exit 31)"
    exit 31
}

# 4. Verifikasi akhir: pastikan tidak ada rule SSH lain yang ALLOW dari Any.
try {
    $suspicious = @()
    $all = Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue | Where-Object { $_.Action -eq 'Allow' -and $_.Enabled -eq 'True' }
    foreach ($r in $all) {
        $pf = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
        if ($pf -and $pf.Protocol -eq 'TCP' -and ($pf.LocalPort -contains "$Port")) {
            $af = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
            if ($af -and ($af.RemoteAddress -contains 'Any')) {
                if ($r.DisplayName -ne $RuleName) {
                    $suspicious += $r.DisplayName
                }
            }
        }
    }
    if ($suspicious.Count -gt 0) {
        Write-Warning ("Masih ada rule lain yang ALLOW port $Port dari ANY: {0}. Hapus manual atau jalankan ulang script." -f ($suspicious -join '; '))
        Write-Error 'ERROR: Firewall belum aman — SSH masih terekspos via rule lain. (exit 32)'
        exit 32
    }
} catch {
    if ($_.Exception.Message -match 'exit 32') { throw }
    Write-Warning "Verifikasi akhir firewall tidak lengkap: $($_.Exception.Message)"
}

Write-Output "OK: Firewall aman. SSH TCP/$Port hanya dari $TailscaleCgnat (Tailscale). Tidak ada ALLOW FROM ANYWHERE."
exit 0
