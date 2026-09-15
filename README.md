# RDP-Awan — Tailscale + Native Windows RDP + Windows App

> Akses RDP privat melalui tailnet Tailscale.
> Tanpa public IP, tanpa port-forwarding router, tanpa membuka TCP 3389 ke Internet.

## Cara kerja

```
PC CLIENT (Windows App + Tailscale, tailnet yang sama)
  | RDP via Tailscale encrypted network
  v
100.x.x.x / MagicDNS (hostname.tailxxxx.ts.net), TCP 3389
  v
PC TARGET (Windows RDP host: TermService + NLA, firewall Tailscale-only)
```

## Mulai cepat (GitHub Actions)

1. Isi Variables/Secrets di `Settings → Secrets and variables → Actions` (lihat tabel di bawah).
2. Buka tab **Actions** → pilih workflow → **Run workflow**:
   - **Windows 11 - RDP (Primary)** — RDP saja.
   - **Hermes-Agent - RDP + Memory Sync (Secondary)** — RDP + sync memori Supabase.
3. Lihat log step `Show Tailscale IP` → blok `RDP READY` berisi IP/MagicDNS.
4. Konek dari Windows App (lihat [Client Setup](#client-setup-windows-app)).

Catatan: GitHub-hosted runner berhenti otomatis setelah ±6 jam (limit GitHub).
Untuk sesi permanen, gunakan self-hosted runner atau jalankan
`setup_rdp_tailscale.ps1` langsung di PC target ([Setup manual](#setup-manual)).

## Konfigurasi (Variables & Secrets)

| Nama | Jenis | Dipakai oleh | Keterangan |
|---|---|---|---|
| `RDP_PASSWORD` | Secret | Primary, Secondary | Password untuk akun default `runneradmin`. Hanya ada di Secrets — tidak pernah ditulis di repo/log. Wajib memenuhi Windows password policy (lihat bawah). Tidak ada user baru yang dibuat. |
| `TAILSCALE_AUTHKEY` | Secret (ephemeral) | Primary, Secondary | Auth key Tailscale. Node otomatis hilang dari tailnet saat runner mati. |
| `SUPABASE_URL`, `SUPABASE_KEY` | Secrets | Secondary saja | Untuk sync memori Hermes-Agent. |

Syarat `RDP_PASSWORD` (jika dilanggar, setup gagal dengan pesan jelas):

- Min. 8 karakter; kombinasi huruf besar + huruf kecil + angka + simbol.
- **Tidak boleh mengandung `runneradmin`** (atau bagian nama >2 karakter) — ini sub-aturan
  complexity Windows yang paling sering menjegal.
- Gunakan nilai yang belum pernah di-commit ke git.

Alur konsumsi:

```
secrets.RDP_PASSWORD ─→ env RDP_PASSWORD ─→ Enable-RdpHost.ps1
                                             (validasi → SetPassword runneradmin via ADSI →
                                              pastikan grup Remote Desktop Users; in-memory only,
                                              tanpa membuat user baru)
```

## Setup manual

Di PC target, PowerShell sebagai **Administrator**, dari folder repo:

```powershell
# Password hanya via environment (jangan taruh password di command line).
# Target akun selalu runneradmin (akun default yang sudah ada).
$env:RDP_PASSWORD = '<password>'
powershell -ExecutionPolicy Bypass -File .\setup_rdp_tailscale.ps1

# Jika Tailscale belum terinstall:
$env:TAILSCALE_AUTHKEY = 'tskey-...'   # opsional, bisa juga via -AuthKey
powershell -ExecutionPolicy Bypass -File .\setup_rdp_tailscale.ps1 -InstallTailscale
```

Urutan `setup_rdp_tailscale.ps1` (idempotent — aman dijalankan berulang):

1. Check Administrator → 2. Check Windows edition → 3. Check Tailscale →
   4. Install Tailscale (hanya dengan `-InstallTailscale`) →
   5. Tailscale service → 6. Tailscale authenticated →
   7. Enable RDP + NLA + set password runneradmin (`Enable-RdpHost.ps1`) →
   8. Firewall Tailscale-only (`Set-RdpFirewallTailscale.ps1`) →
   9. Check TermService → 10. Tampilkan Tailscale IP (`Get-TailscaleIp.ps1`)

Modul individual / port kustom:

```powershell
powershell -ExecutionPolicy Bypass -File .\Enable-RdpHost.ps1
powershell -ExecutionPolicy Bypass -File .\Set-RdpFirewallTailscale.ps1
powershell -ExecutionPolicy Bypass -File .\Get-TailscaleIp.ps1

$env:RDP_PORT = '3389'   # default; ganti bila perlu custom port
```

Contoh output (`RDP READY`):

```
========================================
RDP READY

Tailscale Status : Connected
Tailscale IPv4   : 100.x.x.x
RDP Port         : 3389
NLA              : Enabled
RDP Service      : Running

Windows App:
Connect to:
100.x.x.x

MagicDNS:
hostname.tailxxxx.ts.net
========================================
```

## Client Setup (Windows App)

1. Install + login Tailscale di PC client (tailnet **sama** dengan target).
2. Buka Microsoft Windows App → **Add PC**.
3. PC name: `100.x.x.x` atau `hostname.tailxxxx.ts.net` (dari output di atas).
4. Credentials: username = `runneradmin`, password = nilai `RDP_PASSWORD`
   (diketik manual di client, tidak tersimpan di repo).
5. Connect.

### Display (resolusi & skala)

Pada RDP, **ukuran layar sesi ditentukan oleh client**, bukan host — itu sebabnya
menu Display di dalam sesi remote terkunci (perilaku normal, bukan bug).
Berbeda dengan Chrome Remote Desktop yang menayangkan layar host.

Atur dari Windows App (pengaturan koneksi PC → Display):

- **Resolution**: pilih eksplisit (mis. 1920x1080) atau fit-to-window.
- **Scale/DPI**: mengikuti layar client.
- **Fullscreen / resize jendela**: sesi mengikuti otomatis (dynamic resolution).

## Requirements

- Windows Pro / Enterprise / Education / Server
  (Home / Starter / Single Language tidak mendukung RDP host).
- Akun Tailscale/tailnet (target + client satu tailnet).
- Tailscale di target dan client; Windows App di client.
- Setup dijalankan sebagai **Administrator**.

## Security

- Firewall `Allow RDP from Tailscale only`: RDP hanya dari `100.64.0.0/10`
  (range resmi Tailscale). Rule publik lama (`profile=any`) dihapus otomatis.
  Tidak ada `ALLOW TCP 3389 FROM ANYWHERE`.
- NLA selalu ON; Windows Firewall (`MpsSvc`) selalu Running.
- Akun RDP = `runneradmin` (akun default yang sudah ada, tanpa membuat user baru),
  dipastikan di grup `Remote Desktop Users` (sudah `Administrators` secara default;
  perubahan grup efektif setelah re-login RDP). Password di-set dari `RDP_PASSWORD` secret.
- Kredensial hanya di environment/Secrets; tidak dicetak ke log
  (auth key di-redact, password hanya di memori, tanpa command-line/file).
- Tidak menonaktifkan Defender; tanpa persistence tersembunyi
  (tanpa scheduled-task / Run-key / service custom).
- Tanpa port-forwarding; tanpa RDP publik.

## File repo

| File | Fungsi |
|---|---|
| `setup_rdp_tailscale.ps1` | Entry-point setup (orkestrasi 10 langkah di atas) |
| `Enable-RdpHost.ps1` | Enable RDP + NLA + TermService + set password runneradmin (tanpa user baru) |
| `Set-RdpFirewallTailscale.ps1` | Firewall RDP khusus Tailscale |
| `Get-TailscaleIp.ps1` | Tampilkan IP/MagicDNS format `RDP READY` |
| `Downloads.bat` | Install essentials (tanpa kredensial) |
| `sync_memory.py` | Sync memori Supabase (Secondary) |
| `.github/workflows/Windows 11 - RDP.yml` | Workflow Primary |
| `.github/workflows/Hermes-Agent.yml` | Workflow Secondary |
| `enable_rdp_and_open_port.bat`, `get_public_ip.bat`, `anydesk_manage.ps1` | Legacy/deprecated (lihat bawah) |
| `timelimit.py`, `loop.bat`, `show.bat` | Utilitas non-remote-access |

## Alur workflow

Kedua workflow: Checkout → validasi kredensial → restore cache → `Downloads.bat` →
desktop config → install + `tailscale up` → `Enable-RDP` → firewall → tampilkan IP →
keep-alive loop → save cache (Secondary: + pull/push Supabase).

## Legacy / Deprecated

- **FreeRDP** (`xfreerdp`/`wfreerdp`): tidak dipakai; tidak ada source-nya di repo ini.
- **AnyDesk** (`anydesk_manage.ps1`): keluar dari default, hanya diagnostik manual.
- **Public-IP RDP** (`get_public_ip.bat`): tidak dipakai untuk alamat RDP.
- **Rule `profile=any`** (`enable_rdp_and_open_port.bat` lama): diganti rule Tailscale-only;
  file `.bat`-nya kini wrapper deprecated.
- **Chrome Remote Desktop**: dihapus total dari workflow. Target akhir tetap
  `Tailscale + native Windows RDP + Windows App`.
