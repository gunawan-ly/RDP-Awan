# RDP-Awan — Tailscale + Native Windows RDP + Windows App

> Workflow default sekarang: **Tailscale → Windows RDP → Windows App**.
> RDP **tidak** diekspos ke Internet/public IP. Tanpa port-forwarding router.
> Tanpa membuka TCP 3389 ke Internet.

## Architecture

```
PC CLIENT (Windows App + Tailscale, tailnet yang sama)
  | RDP via Tailscale encrypted network
  v
100.x.x.x / MagicDNS (hostname.tailxxxx.ts.net), TCP 3389
  v
PC TARGET (Windows RDP host: TermService + NLA, firewall Tailscale-only)
```

Yang TIDAK dilakukan:

```
Client -- Internet -- Public IP -- TCP 3389 -- Windows   (DILARANG)
```

## Requirements

- Windows edisi yang mendukung Remote Desktop host:
  Pro / Enterprise / Education / Server (Home / Starter / Single Language tidak didukung).
- Akun Tailscale / tailnet (target + client harus di tailnet yang sama).
- Tailscale terinstall di target dan client.
- Microsoft Windows App / RDP client yang kompatibel di sisi client.
- Jalankan setup sebagai **Administrator**.

## GitHub Actions Configuration (kredensial RDP)

Akun RDP di-provision otomatis oleh `Enable-RdpHost.ps1` dari environment.
Tidak ada password di source code — password hanya ada di GitHub Secrets.

GitHub Actions Variables (`Settings → Secrets and variables → Actions → Variables`):

| Variable | Contoh nilai | Keterangan |
|---|---|---|
| `RDP_USERNAME` | `Awanophile` | Username akun RDP (tidak sensitif, boleh tampil di docs) |

GitHub Actions Secrets (`... → Secrets → New repository secret`):

| Secret | Keterangan |
|---|---|
| `RDP_PASSWORD` | Password akun RDP. Diisi owner dengan password yang diinginkan. Tidak pernah ditulis di repo/log. |
| `TAILSCALE_AUTHKEY` | Auth key Tailscale (ephemeral). Alur existing, tidak diubah. |

Hermes-Agent (Secondary) juga butuh `SUPABASE_URL` + `SUPABASE_KEY` seperti sebelumnya.

Alur konsumsi:

```
vars.RDP_USERNAME ──→ env RDP_USERNAME ──┐
secrets.RDP_PASSWORD ─→ env RDP_PASSWORD ─┴─→ Enable-RdpHost.ps1
                                              (validasi → create/update user →
                                               Remote Desktop Users, via SecureString)
```

Manual setup (di luar Actions):

```powershell
# Prefer environment variables; jangan taruh password di command line.
$env:RDP_USERNAME = 'nama-user-rdp'
$env:RDP_PASSWORD = '<password>'
powershell -ExecutionPolicy Bypass -File .\setup_rdp_tailscale.ps1
```

## Setup Target PC (satu entry-point)

```powershell
# PowerShell sebagai Administrator, dari folder repo:
powershell -ExecutionPolicy Bypass -File .\setup_rdp_tailscale.ps1

# Jika Tailscale belum terinstall dan ingin diinstall otomatis dari URL resmi:
$env:TAILSCALE_AUTHKEY = 'tskey-...'   # opsional, bisa juga via -AuthKey
powershell -ExecutionPolicy Bypass -File .\setup_rdp_tailscale.ps1 -InstallTailscale
```

Urutan `setup_rdp_tailscale.ps1` (PRD Fase 13, idempotent):

1. Check Administrator
2. Check Windows edition
3. Check Tailscale (`tailscale.exe`)
4. Install Tailscale (hanya dengan `-InstallTailscale`, dari `https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe`)
5. Pastikan Tailscale service berjalan (service resmi, tanpa custom persistence)
6. Pastikan Tailscale authenticated (`tailscale up --authkey=...` hanya jika key tersedia;
   jika belum login, script berhenti dengan instruksi `tailscale up` manual)
7. Enable RDP (`Enable-RdpHost.ps1`)
8. Enable NLA (bagian dari modul yang sama, selalu ON)
9. Configure firewall Tailscale-only (`Set-RdpFirewallTailscale.ps1`)
10. Check TermService Running
11. Obtain Tailscale IP (`Get-TailscaleIp.ps1`)
12. Print final connection info (format `RDP READY`)

Modul individual juga bisa dijalankan terpisah:

```powershell
powershell -ExecutionPolicy Bypass -File .\Enable-RdpHost.ps1
powershell -ExecutionPolicy Bypass -File .\Set-RdpFirewallTailscale.ps1
powershell -ExecutionPolicy Bypass -File .\Get-TailscaleIp.ps1
```

Custom port (kompatibilitas `RDP_PORT` lama, default `3389`):

```powershell
$env:RDP_PORT = '3389'
powershell -ExecutionPolicy Bypass -File .\setup_rdp_tailscale.ps1
```

Contoh output `Get-TailscaleIp.ps1`:

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
3. PC name:
   - `100.x.x.x` (dari output di atas), atau
   - `hostname.tailxxxx.ts.net` (MagicDNS jika tersedia).
4. Credentials: username = nilai `RDP_USERNAME`, password = nilai `RDP_PASSWORD`
   (keduanya diketik manual di client, tidak tersimpan di repo).
5. Connect.

### Display (resolusi & skala)

Berbeda dengan Chrome Remote Desktop (yang menayangkan layar host sehingga
resolusi diubah di sisi host), pada RDP **ukuran layar sesi ditentukan oleh
client saat konek**. Itu sebabnya menu Display di dalam sesi remote terkunci —
ini perilaku normal RDP, bukan bug setup. Tidak ada yang perlu diubah di sisi
host/GitHub workflow untuk ini.

Atur dari Windows App (pengaturan koneksi PC → Display), sebelum atau saat konek:

- **Resolution**: pilih resolusi eksplisit (mis. 1920x1080) atau mode fit-to-window.
- **Scale/DPI**: atur skala tampilan mengikuti layar client.
- **Fullscreen / resize jendela**: sesi mengikuti ukuran jendela secara otomatis
  (dynamic resolution) — cara tercepat mendapat tampilan yang pas.
- Simpan sebagai pengaturan koneksi PC tersebut agar berlaku setiap konek.

> Jangan menyimpan password Windows di repository.
> Penyimpanan credential lokal di Windows App adalah pilihan user di client,
> bukan sesuatu yang dilakukan script.

## Security

- RDP hanya dari `100.64.0.0/10` (range CGNAT resmi Tailscale) via rule
  `Allow RDP from Tailscale only`. Tidak ada `ALLOW TCP 3389 FROM ANYWHERE`.
- Legacy rule publik `Allow RDP TCP 3389 ... profile=any` dihapus otomatis oleh
  `Set-RdpFirewallTailscale.ps1`.
- NLA selalu ON. Windows Firewall (`MpsSvc`) selalu Running, tidak pernah di-disable.
- Tidak menonaktifkan Defender, tidak membuat hidden user, tidak mengubah password
  akun lain di luar akun RDP yang di-provision,
  tidak membuat scheduled-task / Run-key / service custom tersembunyi.
- Secret tidak di-hardcode: `TAILSCALE_AUTHKEY`, `RDP_PASSWORD` dibaca dari
  environment / GitHub Secrets, tidak pernah dicetak ke log
  (auth key di-redact saat `tailscale up`; password hanya di memori via SecureString).
- Jangan melakukan port-forwarding router atau membuka 3389 ke Internet.

## Files

| File | Status | Keterangan |
|---|---|---|
| `setup_rdp_tailscale.ps1` | ADDED (entry-point) | Orkestrasi 12 langkah PRD |
| `Enable-RdpHost.ps1` | MODIFIED | Enable RDP + NLA + TermService + provisioning akun RDP dari env (cek admin + edisi) |
| `Set-RdpFirewallTailscale.ps1` | ADDED | Firewall Tailscale-only, hapus legacy `profile=any` |
| `Get-TailscaleIp.ps1` | ADDED | Tampilkan Tailscale IP / MagicDNS format `RDP READY` |
| `enable_rdp_and_open_port.bat` | MODIFIED (deprecated wrapper) | Diteruskan ke 2 modul `.ps1` aman; jangan dipakai langsung |
| `get_public_ip.bat` | MODIFIED (deprecated untuk RDP) | Dipertahankan untuk non-RDP; RDP pakai Tailscale IP |
| `anydesk_manage.ps1` | MODIFIED (header deprecated) | Tidak dipanggil setup/workflows baru |
| `.github/workflows/Windows 11 - RDP.yml` (`Windows 11 - RDP (Primary)`) | MODIFIED | CRD dihapus, diganti RDP Tailscale-only |
| `.github/workflows/Hermes-Agent.yml` | MODIFIED | CRD dihapus, diganti RDP Tailscale-only; cache + Supabase dipertahankan |
| `Downloads.bat` | MODIFIED | Baris password plaintext dihapus; provisioning via `Enable-RdpHost.ps1` |
| `sync_memory.py` | KEPT | Pull/push Supabase via env, tidak terkait RDP |
| `timelimit.py`, `loop.bat`, `show.bat` | KEPT | Utilitas non-remote-access |

## Legacy / Deprecated (PRD Fase 19)

- **FreeRDP remote workflow** (`freerdp` / `xfreerdp` / `wfreerdp`):
  tidak ditemukan di working copy ini (hanya disebut di PRD).
  Keputusan: tidak ada dependency FreeRDP untuk remote-access utama; tidak ada
  source upstream yang dihapus karena memang tidak ada.
- **AnyDesk workflow** (`anydesk_manage.ps1`): keluar dari default.
  File dipertahankan untuk diagnostik manual saja.
- **Public-IP based RDP** (`get_public_ip.bat`, `api.ipify.org`):
  tidak lagi dipakai untuk alamat RDP. Gunakan Tailscale IP / MagicDNS.
- **Public firewall RDP rule** (`profile=any` di `enable_rdp_and_open_port.bat` lama):
  dihapus/diganti rule Tailscale-only. File `.bat` lama menjadi wrapper deprecated.
- **Chrome Remote Desktop** (`chromeremotedesktophost.msi`, `remoting_start_host --code --pin=123456`):
  dihapus total dari kedua workflow. Bukan dependency lagi.
  Target akhir: `Tailscale + native Windows RDP + Microsoft Windows App`,
  bukan `Tailscale + CRD + RDP` maupun `CRD + RDP`.

## GitHub Workflows

Kedua workflow (`Windows 11 - RDP.yml` = Primary, `Hermes-Agent.yml` = Secondary + Memory Sync) sekarang:

1. Checkout → validasi konfigurasi kredensial → restore cache → `Downloads.bat` → desktop config.
2. Install + `tailscale up` (auth via `${{ secrets.TAILSCALE_AUTHKEY }}`).
3. `Enable-RdpHost.ps1` (env dari `vars.RDP_USERNAME` / `secrets.RDP_PASSWORD`) → `Set-RdpFirewallTailscale.ps1` → `Get-TailscaleIp.ps1`.
4. Keep-alive loop (pesan Tailscale + Windows RDP).
5. Save cache (dan push Supabase memory untuk Hermes-Agent).

- Akun RDP (`RDP_USERNAME`) adalah akun terpisah dengan grup
  `Remote Desktop Users` saja (bukan Administrators); akun internal runner
  tidak diubah, tidak dihapus, tidak di-rename.
