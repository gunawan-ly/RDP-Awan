<#
.SYNOPSIS
  Enable native Windows OpenSSH Server (sshd) dan setup password akun
  default runneradmin dari Secret. Pasangan SSH dari Enable-RdpHost.ps1.
  Idempotent. Tidak menyentuh Defender atau persistence.

.DESCRIPTION
  - Cek Administrator.
  - Install OpenSSH Server:
      utama   : Windows Capability "OpenSSH.Server~~~~0.0.1.0".
      cadangan: paket resmi PowerShell/Win32-OpenSSH (GitHub release)
                jika capability gagal / sshd.exe tidak muncul.
  - Pastikan sshd_config ada; PasswordAuthentication tidak dimatikan
    (login password harus bisa, karena autentikasi memakai password
    akun Windows). Port kustom via -SshPort / env SSH_PORT (default 22).
  - DefaultShell SSH diarahkan ke PowerShell (pwsh jika ada, else
    Windows PowerShell 5.1 yang selalu tersedia).
  - Pastikan service sshd Start=auto dan Running.
  - Setup akun SSH: pakai akun default yang sudah ada 'runneradmin',
    set password dari $env:RDP_PASSWORD (GitHub Actions
    secrets.RDP_PASSWORD — secret yang SAMA dengan workflow RDP,
    agar tidak perlu secret baru). TIDAK membuat user baru.
    Nilai password tidak pernah dicetak ke output.
  - Tidak membuka firewall di sini (lihat Set-SshFirewallTailscale.ps1).
  - Tidak menonaktifkan security feature apapun.

.PARAMETER SshPort
  TCP port SSH. Default 22. Bisa juga via $env:SSH_PORT.

.EXAMPLE
$env:RDP_PASSWORD = '<dari GitHub Secrets>'
  powershell -ExecutionPolicy Bypass -File .\Enable-SshHost.ps1
#>
[CmdletBinding()]
param(
    [int]$SshPort = 0
)

$ErrorActionPreference = 'Stop'

# Rilis resmi Win32-OpenSSH untuk jalur cadangan (dipin agar reproducible).
$OpenSshZipUrl = 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.4.0.0p1-Preview/OpenSSH-Win64.zip'
$OpenSshDir = 'C:\Program Files\OpenSSH'

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
        Write-Warning "env SSH_PORT='$env:SSH_PORT' tidak valid, pakai 22."
    }
    return 22
}

# --- Main ---
if (-not (Test-IsAdmin)) {
    Write-Error 'ERROR: Script harus dijalankan sebagai Administrator. Klik kanan PowerShell -> Run as Administrator. (exit 10)'
    exit 10
}

$Port = Get-SshPort -Override $SshPort
if ($Port -le 0 -or $Port -gt 65535) {
    Write-Error "ERROR: SSH port tidak valid: $Port. (exit 11)"
    exit 11
}

try {
    # 1. Install OpenSSH Server bila sshd.exe belum ada.
    $sshdExe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
    if (Test-Path $sshdExe) {
        Write-Output 'OpenSSH Server: sudah terinstall (idempotent, skip).'
    } else {
        $installed = $false
        try {
            Write-Output 'OpenSSH Server: install via Windows Capability...'
            $cap = Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' -ErrorAction Stop
            if ($cap -and $cap.RestartNeeded) { Write-Warning 'Capability meminta restart; lanjut dulu, service dicek di langkah berikutnya.' }
            $installed = Test-Path $sshdExe
        } catch {
            Write-Warning "Capability gagal: $($_.Exception.Message) — beralih ke paket Win32-OpenSSH resmi."
        }
        if (-not $installed) {
            Write-Output 'OpenSSH Server: install via paket Win32-OpenSSH (GitHub release resmi)...'
            $zip = Join-Path $env:TEMP 'OpenSSH-Win64.zip'
            Invoke-WebRequest -Uri $OpenSshZipUrl -OutFile $zip -UseBasicParsing -ErrorAction Stop
            if (Test-Path $OpenSshDir) { Remove-Item $OpenSshDir -Recurse -Force }
            Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force -ErrorAction Stop
            Move-Item -Path (Join-Path $env:TEMP 'OpenSSH-Win64') -Destination $OpenSshDir -Force
            & (Join-Path $OpenSshDir 'install-sshd.ps1')
            $sshdExe = Join-Path $OpenSshDir 'sshd.exe'
            if (-not (Test-Path $sshdExe)) { throw 'sshd.exe tetap tidak ditemukan setelah install paket.' }
        }
        Write-Output 'OpenSSH Server: terinstall.'
    }

    # 2. sshd_config: pastikan ada + PasswordAuthentication tidak 'no' + port.
    $configDir = Join-Path $env:ProgramData 'ssh'
    $configPath = Join-Path $configDir 'sshd_config'
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    if (-not (Test-Path $configPath)) {
        # Template minimal setara bawaan OpenSSH Windows.
        @(
            '# sshd_config dibuat oleh Enable-SshHost.ps1 (bawaan OpenSSH setara)'
            'PubkeyAuthentication yes'
            'PasswordAuthentication yes'
            'Subsystem sftp sftp-server.exe'
            'Match Group administrators'
            '       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys'
        ) | Set-Content -Path $configPath -Encoding ascii
        Write-Output 'sshd_config: dibuat dari template minimal.'
    }
    $cfg = Get-Content -Path $configPath
    $changed = $false
    if ($cfg -match '^\s*PasswordAuthentication\s+no') {
        $cfg = $cfg -replace '^\s*PasswordAuthentication\s+no', 'PasswordAuthentication yes'
        $changed = $true
        Write-Output 'sshd_config: PasswordAuthentication diperbaiki ke yes.'
    }
    if ($Port -ne 22) {
        if ($cfg -match '^\s*#?\s*Port\s+\d+') {
            $cfg = $cfg -replace '^\s*#?\s*Port\s+\d+', "Port $Port"
        } else {
            $cfg = @("Port $Port") + $cfg
        }
        $changed = $true
        Write-Output "sshd_config: Port diset ke $Port."
    }
    if ($changed) { $cfg | Set-Content -Path $configPath -Encoding ascii }

    # 3. DefaultShell: pwsh bila ada, else Windows PowerShell 5.1.
    $shellPath = $null
    $pwsh = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
    if ($pwsh) { $shellPath = $pwsh.Source }
    if (-not $shellPath) {
        $cand = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (Test-Path $cand) { $shellPath = $cand }
    }
    if ($shellPath) {
        $key = 'HKLM:\SOFTWARE\OpenSSH'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        $cur = (Get-ItemProperty -Path $key -Name 'DefaultShell' -ErrorAction SilentlyContinue).DefaultShell
        if ($cur -ne $shellPath) {
            Set-ItemProperty -Path $key -Name 'DefaultShell' -Value $shellPath -Type String -Force
            Write-Output "SSH DefaultShell: $shellPath"
        } else {
            Write-Output 'SSH DefaultShell: sudah sesuai (idempotent, skip).'
        }
    } else {
        Write-Warning 'Tidak ada pwsh/powershell.exe ditemukan; DefaultShell tidak diubah.'
    }

    # 4. Service sshd auto + running.
    $svc = Get-Service -Name 'sshd' -ErrorAction Stop
    if ($svc.StartType -ne 'Automatic') {
        Set-Service -Name 'sshd' -StartupType Automatic -ErrorAction Stop
        Write-Output 'sshd: startup set to Automatic.'
    } else {
        Write-Output 'sshd: already Automatic (idempotent, skip).'
    }
    if ($svc.Status -ne 'Running') {
        Start-Service -Name 'sshd' -ErrorAction Stop
        Start-Sleep -Seconds 2
        $svc.Refresh()
        if ($svc.Status -ne 'Running') {
            Write-Error 'ERROR: sshd gagal start setelah dicoba. (exit 20)'
            exit 20
        }
        Write-Output 'sshd: started.'
    } else {
        # Config mungkin berubah di langkah 2; restart agar efektif.
        if ($changed) {
            Restart-Service -Name 'sshd' -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Output 'sshd: restarted (config berubah).'
        } else {
            Write-Output 'sshd: already Running (idempotent, skip).'
        }
    }
} catch {
    Write-Error "ERROR: Gagal mengaktifkan SSH host: $($_.Exception.Message) (exit 21)"
    exit 21
}

# --- 5. Setup akun SSH default (otoritatif, idempotent, tanpa user baru) ---
# Target: akun bawaan 'runneradmin'. Metode: ADSI WinNT provider (sama
# seperti Enable-RdpHost.ps1; cmdlet LocalAccounts terbukti melempar
# InvalidPasswordException di GitHub-hosted runner).
# Password HANYA dari runtime env (secrets.RDP_PASSWORD yang sama dengan
# workflow RDP, atau env manual). Tidak ada password di source,
# command-line, file, atau output.
try {
    $sshUser = 'runneradmin'
    $sshPass = $env:RDP_PASSWORD
    if ([string]::IsNullOrWhiteSpace($sshPass)) {
        Write-Error 'ERROR: RDP_PASSWORD GitHub Actions Secret is not configured. (exit 61)'
        exit 61
    }

    $compName = $env:COMPUTERNAME
    $existing = Get-LocalUser -Name $sshUser -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Error "ERROR: Akun default '$sshUser' tidak ditemukan di komputer ini. Setup tanpa user baru dibatalkan (tidak membuat akun). (exit 64)"
        exit 64
    } else {
        $adu = [ADSI]"WinNT://$compName/$sshUser,user"
        $adu.SetPassword($sshPass)
        # Pastikan akun enabled (clear UF_ACCOUNTDISABLE), tanpa mengubah flag lain.
        $adu.UserFlags = $adu.UserFlags.Value -band (-bnot 2)
        $adu.SetInfo()
        Write-Output "SSH user: password for default account '$sshUser' updated (idempotent)."
    }
    # Login SSH untuk admin memakai administrators_authorized_keys bila
    # kunci dipakai, dan password akun untuk login password; yang wajib:
    # akun harus Administrators agar sesi SSH mendapat hak penuh.
    # runneradmin sudah Administrators secara default; verifikasi read-only.
    $adminGroup = [ADSI]"WinNT://$compName/Administrators,group"
    $adminMembers = @($adminGroup.Members() | ForEach-Object {
        $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null)
    })
    if ($adminMembers -contains $sshUser) {
        Write-Output "SSH user: '$sshUser' already in 'Administrators' (idempotent, skip)."
    } else {
        Write-Warning "SSH user: '$sshUser' is NOT in 'Administrators' (tidak ditambahkan otomatis; setup tanpa user baru)."
    }
} catch {
    # Rantai pesan error lengkap agar bisa didiagnosis, TAPI scrub dulu
    # nilai password agar tidak bocor ke log. Username tidak sensitif.
    $msgs = @()
    $e = $_.Exception
    while ($e) { $msgs += $e.Message; $e = $e.InnerException }
    $detail = ($msgs -join ' <-- ')
    if (-not [string]::IsNullOrWhiteSpace($sshPass)) {
        $detail = $detail -replace [regex]::Escape($sshPass), '(redacted)'
    }
    if ($detail -match 'password|policy|complex|length|credential') {
        $detail += ' [HINT: pastikan RDP_PASSWORD memenuhi Local Security Policy (panjang min. & kompleksitas).]'
    }
    Write-Error "ERROR: Gagal setup akun SSH default: $detail (exit 62)"
    exit 62
} finally {
    if (Test-Path variable:\sshPass) { $sshPass = $null; Remove-Variable sshPass -ErrorAction SilentlyContinue }
    [GC]::Collect()
}

# --- 6. Verifikasi port mendengarkan ---
$listening = $false
try {
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($conn) { $listening = $true }
} catch {}
if ($listening) {
    Write-Output "sshd: LISTENING di TCP/$Port."
} else {
    Write-Warning "sshd: belum terlihat LISTENING di TCP/$Port (cek 'Get-Service sshd' dan log Event Viewer > OpenSSH)."
}

Write-Output "OK: Windows SSH host aktif. Port=$Port sshd=Running User=$sshUser."
exit 0
