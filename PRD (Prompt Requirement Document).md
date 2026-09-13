Anda adalah autonomous coding agent. Tugas Anda adalah memodifikasi repository berikut secara langsung:

Repository:
https://github.com/gunawan-ex/freerdpppp

TUJUAN UTAMA

Ubah workflow remote-access repository ini sehingga:

1. FreeRDP tidak lagi menjadi mekanisme utama untuk melakukan koneksi RDP.
2. AnyDesk tidak lagi menjadi mekanisme remote-access utama.
3. PC Windows target menjalankan native Windows Remote Desktop (RDP).
4. Akses RDP dari sisi client dilakukan menggunakan Microsoft Windows App / Remote Desktop client.
5. Konektivitas antar-PC menggunakan Tailscale.
6. RDP TIDAK boleh diekspos secara langsung ke Internet/public IP.
7. Tidak membutuhkan port forwarding router.
8. Tidak membutuhkan membuka TCP 3389 ke Internet.
9. Tetap mempertahankan script/utilitas repository yang tidak berhubungan langsung dengan mekanisme remote-access, kecuali memang perlu diperbaiki agar tidak konflik.
10. Semua perubahan harus dibuat langsung pada working copy hasil clone repository.

Repository ini adalah fork/derivasi dari FreeRDP dan sudah memiliki berbagai automation script. Jangan mengasumsikan struktur repository berdasarkan nama file saja. Audit repository aktual terlebih dahulu.

---

FASE 1 — CLONE DAN AUDIT

Clone repository:

https://github.com/gunawan-ex/freerdpppp

Buat branch kerja baru, misalnya:

agent/tailscale-windows-app-rdp

Jangan langsung menghapus file.

Pertama lakukan audit menyeluruh terhadap repository.

Periksa minimal:

- README
- seluruh ".bat"
- seluruh ".cmd"
- seluruh ".ps1"
- seluruh ".psm1"
- seluruh ".py"
- seluruh workflow ".github/workflows/*"
- konfigurasi FreeRDP
- konfigurasi AnyDesk
- konfigurasi Tailscale
- script download/install
- script persistence
- script networking
- script firewall
- script public IP
- script loop/automation
- seluruh referensi terhadap:
  - freerdp
  - xfreerdp
  - wfreerdp
  - AnyDesk
  - Chrome Remote Desktop
  - RDP
  - mstsc
  - Windows App
  - Tailscale
  - port 3389
  - firewall
  - public IP
  - NAT
  - tunneling
  - relay

Gunakan pencarian repository, misalnya ripgrep/grep, untuk menemukan semua referensi tersebut.

Buat pemetaan internal:

FILE → FUNGSI → DIPERTAHANKAN / DIMODIFIKASI / DEPRECATED / DIHAPUS

Jangan menghapus sesuatu hanya karena namanya terlihat tidak relevan.

---

FASE 2 — PAHAMI ARSITEKTUR YANG DIINGINKAN

Arsitektur target harus seperti ini:

CLIENT
|
| Tailscale encrypted network
|
v
WINDOWS TARGET
|
+-- Windows Remote Desktop Services
|
+-- TCP 3389 hanya melalui jaringan/interface Tailscale
|
+-- Windows App / Remote Desktop client pada sisi client

Konsepnya:

Client Windows App
|
| RDP
|
| melalui Tailscale
v
100.x.x.x / MagicDNS
|
v
Windows RDP host

Jangan membuat:

Client
|
Internet
|
Public IP
|
TCP 3389
|
Windows

Jangan menggunakan public IP sebagai alamat RDP.

Jangan membuat port forwarding router.

Jangan menyarankan membuka 3389 ke Internet.

---

FASE 3 — AUDIT TAILSCALE YANG SUDAH ADA

Repository kemungkinan sudah memiliki script/configuration Tailscale.

Cari dan pahami implementasi yang sudah ada.

Jangan membuat instalasi Tailscale kedua jika repository sudah memiliki mekanisme yang benar.

Periksa:

- apakah Tailscale sudah di-download
- apakah Tailscale sudah di-install
- apakah service Tailscale sudah digunakan
- bagaimana authentication dilakukan
- apakah auth key digunakan
- apakah auth key hardcoded
- apakah environment variable digunakan
- apakah Tailscale dijalankan sebagai Windows service
- apakah Tailscale tetap aktif setelah reboot
- apakah unattended mode digunakan
- bagaimana mendapatkan IP Tailscale
- apakah MagicDNS digunakan
- apakah ACL/Tailnet policy diperlukan
- apakah ada script yang membuka firewall
- apakah ada script yang mengambil public IP

Jika authentication credential/token/auth key ditemukan di source code:

JANGAN mengekspos atau mencetak secret tersebut.

Jika secret sudah hardcoded di repository, tandai sebagai SECURITY ISSUE dan pindahkan ke mekanisme konfigurasi yang aman, misalnya environment variable atau input runtime.

Jangan commit secret baru.

---

FASE 4 — WINDOWS RDP HOST

Buat atau refactor script yang bertanggung jawab mengaktifkan Windows RDP.

Nama yang direkomendasikan:

enable_rdp.bat

atau jika struktur repository lebih cocok:

enable_rdp.ps1

Pilih format yang paling konsisten dengan repository.

Script harus:

1. Memastikan dijalankan sebagai Administrator.
2. Memeriksa Windows edition.
3. Memberikan pesan yang jelas jika edition Windows tidak mendukung RDP host.
4. Mengaktifkan Remote Desktop.
5. Mengaktifkan Network Level Authentication (NLA).
6. Memastikan service TermService aktif.
7. Memastikan TermService otomatis start.
8. Tidak menonaktifkan security feature Windows yang tidak diperlukan.
9. Tidak menonaktifkan Windows Defender.
10. Tidak membuat akun Windows tersembunyi.
11. Tidak membuat credential tersembunyi.
12. Tidak mengubah password user.
13. Tidak membuat persistence yang tidak diperlukan.

Gunakan native Windows mechanism.

Jangan menggunakan FreeRDP untuk menjalankan RDP server.

Jangan menggunakan Chrome Remote Desktop sebagai RDP host.

---

FASE 5 — FIREWALL

Ini bagian yang sangat penting.

Repository saat ini mungkin mempunyai script seperti:

enable_rdp_and_open_port.bat

yang membuka RDP firewall secara luas.

Audit rule tersebut.

JANGAN mempertahankan konfigurasi seperti:

profile=any

jika itu membuat RDP dapat diakses melalui network interface publik.

Tujuan akhir:

RDP hanya dapat diakses melalui jaringan Tailscale.

Idealnya firewall rule membatasi:

- TCP
- RDP port
- remote source/interface yang sesuai dengan Tailscale

Namun jangan membuat rule yang bergantung pada asumsi interface/adapter name yang rapuh.

Gunakan pendekatan Windows Firewall yang robust dan terdokumentasi.

Jika pembatasan berdasarkan interface alias Tailscale tidak portable pada semua instalasi, gunakan kombinasi rule yang aman berdasarkan kebutuhan Windows Firewall dan Tailscale.

PENTING:

Jangan menghapus seluruh firewall protection Windows.

Jangan membuat rule:

ALLOW TCP 3389 FROM ANYWHERE

Jangan membuka port 3389 ke public Internet.

Jika ada legacy script yang membuka RDP secara publik, refactor atau deprecate script tersebut.

---

FASE 6 — TAILSCALE SERVICE

Pastikan Tailscale dapat berjalan tanpa user harus membuka GUI secara manual.

Target:

Windows boot
↓
Tailscale service aktif
↓
Tailnet connected
↓
RDP service aktif
↓
PC siap diakses menggunakan Windows App

Jika Tailscale mendukung unattended mode untuk skenario tersebut, gunakan pendekatan resmi Tailscale.

Jangan membuat custom persistence mechanism seperti:

- scheduled task tersembunyi
- registry Run key
- startup malware-like mechanism
- service custom yang tidak diperlukan

Gunakan service resmi Tailscale.

---

FASE 7 — DETEKSI TAILSCALE IP

Buat utility/script untuk menampilkan alamat Tailscale PC.

Contoh:

get_tailscale_ip.bat

atau PowerShell yang lebih robust.

Output harus mudah dipahami:

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

========================================

Jika MagicDNS tersedia, tampilkan juga hostname.

Contoh:

MagicDNS:
hostname.tailxxxx.ts.net

Jangan menggunakan public IP untuk instruksi RDP.

Jika Tailscale tidak connected, tampilkan error yang jelas.

---

FASE 8 — WINDOWS APP

Dokumentasikan bahwa sisi client menggunakan Microsoft Windows App.

Jelaskan konfigurasi client secara singkat.

Target:

Windows App
↓
Add PC
↓
PC name:
100.x.x.x

atau:

hostname.tailxxxx.ts.net

Credentials:

Windows account pada PC target.

Jangan memasukkan password Windows ke repository.

Jangan membuat credential otomatis.

Jangan menyimpan password dalam plain text.

Jika Windows App memiliki opsi untuk menyimpan credential secara lokal, dokumentasikan sebagai pilihan user, bukan sesuatu yang dilakukan script.

---

FASE 9 — FREE RDP

Audit semua penggunaan FreeRDP.

Tujuan akhir:

FreeRDP bukan lagi dependency untuk remote-access utama.

Namun jangan membabi buta menghapus seluruh source FreeRDP jika repository memang masih membutuhkannya untuk tujuan lain.

Tentukan berdasarkan audit:

A. Jika FreeRDP hanya digunakan untuk melakukan remote connection:

- deprecate/remove workflow tersebut.

B. Jika source FreeRDP merupakan core repository atau masih dibutuhkan:

- pertahankan source-nya,
- tetapi ubah automation agar tidak mengandalkan FreeRDP untuk koneksi PC target.

Dokumentasikan keputusan tersebut.

Jangan menghapus source code upstream secara massal hanya untuk membuat repository lebih kecil.

---

FASE 10 — ANYDESK

Audit:

anydesk_manage.ps1

dan semua referensi AnyDesk.

Jika AnyDesk hanya digunakan sebagai alternatif remote access:

- jangan gunakan lagi dalam workflow default.
- jangan membuat AnyDesk otomatis terinstall.
- jangan membuat AnyDesk otomatis berjalan untuk remote access.
- jangan menghapus file tanpa memahami dependency-nya.

Jika file tidak lagi diperlukan, ubah menjadi deprecated atau hapus hanya jika benar-benar aman.

Dokumentasikan perubahan.

---

FASE 11 — PUBLIC IP

Audit:

get_public_ip.bat

dan seluruh penggunaan public IP.

RDP workflow baru tidak boleh bergantung pada public IP.

Jika script public IP dipakai untuk fungsi lain yang tidak berhubungan dengan RDP, pertahankan.

Jika hanya digunakan untuk menentukan alamat RDP, deprecated/remove penggunaannya.

Dokumentasi RDP harus selalu mengarahkan user ke:

Tailscale IP
atau
MagicDNS hostname.

---

FASE 12 — CHROME REMOTE DESKTOP

Jangan menginstal atau mengkonfigurasi Chrome Remote Desktop untuk workflow baru.

Jika repository memiliki referensi CRD:

- audit dulu.
- jika memang legacy remote-access, deprecate.
- jangan menjadikan CRD dependency.

Target akhir adalah:

Tailscale + Windows RDP + Windows App

bukan:

Tailscale + CRD + RDP

dan bukan:

CRD + RDP.

---

FASE 13 — MODE INSTALL / SETUP

Jika repository memiliki workflow installation/setup, buat agar user dapat menjalankan satu entry-point utama.

Contoh:

setup_rdp_tailscale.bat

atau:

setup.ps1

Entry point tersebut idealnya:

1. Check Administrator.
2. Check Windows edition.
3. Check Tailscale.
4. Install Tailscale jika repository memang memiliki installer mechanism yang sesuai.
5. Pastikan Tailscale service berjalan.
6. Pastikan Tailscale authenticated.
7. Enable RDP.
8. Enable NLA.
9. Configure firewall.
10. Check TermService.
11. Obtain Tailscale IP.
12. Print final connection information.

Jangan meminta credential rahasia secara otomatis jika tidak diperlukan.

Jika authentication Tailscale memang membutuhkan user action, hentikan di titik tersebut dengan instruksi yang jelas.

---

FASE 14 — IDEMPOTENCY

Semua setup script harus idempotent.

Artinya:

Jika dijalankan:

setup
setup
setup
setup

hasilnya tidak:

- membuat duplicate firewall rules
- membuat duplicate services
- merusak konfigurasi
- menambah duplicate scheduled tasks
- mengubah port berulang-ulang
- membuat banyak entry registry
- membuat error hanya karena konfigurasi sudah ada.

Script kedua kali harus mendeteksi bahwa konfigurasi sudah benar dan melanjutkan.

---

FASE 15 — ERROR HANDLING

Script harus memberikan error yang jelas.

Minimal tangani:

- bukan Administrator
- Windows edition tidak mendukung RDP
- Tailscale tidak terinstall
- Tailscale service tidak berjalan
- Tailscale belum authenticated
- Tailscale tidak connected
- tidak ada Tailscale IPv4
- TermService gagal start
- firewall rule gagal dibuat
- port RDP berbeda dari yang diasumsikan
- Windows Firewall service tidak tersedia

Jangan menggunakan:

«Setup successful»

jika salah satu komponen utama sebenarnya gagal.

Gunakan exit codes yang masuk akal.

---

FASE 16 — PORT RDP

Jangan mengubah port RDP tanpa alasan.

Default:

3389/TCP

lebih baik dipertahankan kecuali repository memiliki alasan kuat menggunakan custom port.

Jika repository saat ini memiliki variable:

RDP_PORT

pertahankan compatibility jika memungkinkan.

Tetapi pastikan dokumentasi Windows App menunjukkan port yang benar jika custom port memang digunakan.

Contoh:

100.x.x.x:3389

atau:

hostname.tailxxxx.ts.net:3389

---

FASE 17 — SECURITY REVIEW

Setelah implementasi selesai, lakukan security review.

Cari:

- hardcoded password
- hardcoded Tailscale auth key
- hardcoded API token
- public RDP exposure
- firewall profile any
- port forwarding instructions
- insecure registry changes
- disabled NLA
- disabled Windows Firewall
- hidden users
- persistence mechanism yang mencurigakan
- plaintext credentials
- download URL HTTP
- script execution tanpa verifikasi jika bisa dihindari

Jangan menambahkan bypass keamanan hanya agar script "lebih mudah".

NLA harus tetap enabled.

Windows Firewall harus tetap aktif.

---

FASE 18 — DOCUMENTATION

Update README agar workflow baru jelas.

Dokumentasikan minimal:

Architecture

Tailscale
↓
Windows RDP
↓
Windows App

Requirements

- Windows edition yang mendukung Remote Desktop host
- Tailscale account/tailnet
- Tailscale pada target
- Tailscale pada client
- Microsoft Windows App / compatible RDP client

Setup target PC

Jalankan setup script sebagai Administrator.

Client setup

Install/login Tailscale.

Kemudian buka Windows App.

Add PC menggunakan:

100.x.x.x

atau MagicDNS hostname.

Security

Jelaskan bahwa RDP tidak perlu dibuka ke Internet.

Jangan menyarankan:

port forwarding
public RDP
3389 exposed to Internet.

---

FASE 19 — DOCUMENT LEGACY

Jangan sekadar menghapus functionality lama.

Buat bagian:

Legacy / Deprecated

yang menjelaskan jika ada:

- FreeRDP remote workflow
- AnyDesk workflow
- public IP based RDP
- public firewall RDP rule

dan bagaimana workflow baru menggantikannya.

---

FASE 20 — TESTING

Lakukan testing sebanyak mungkin pada environment yang tersedia.

Minimal lakukan static checks.

Untuk BAT/CMD:

- syntax review
- variable expansion review
- quoting review
- administrator detection review
- errorlevel handling

Untuk PowerShell:

- parser validation
- syntax validation
- execution-path review

Untuk Python:

- compile check
- lint/static check jika tooling tersedia

Untuk GitHub Actions:

- YAML syntax validation
- review runner compatibility
- review Windows runner commands

Jangan melakukan destructive test terhadap environment host.

Jika tidak dapat benar-benar melakukan koneksi RDP/Tailscale karena environment tidak menyediakan Windows GUI/network environment, katakan dengan jelas bahwa test tersebut tidak dapat dilakukan dan lakukan static validation semaksimal mungkin.

---

FASE 21 — GIT DIFF REVIEW

Sebelum selesai:

jalankan:

git status
git diff --stat
git diff

Review setiap perubahan.

Pastikan:

- tidak ada secret
- tidak ada binary besar yang tidak diperlukan
- tidak ada file temporary
- tidak ada credential
- tidak ada debug output sensitif
- tidak ada perubahan unrelated
- tidak ada accidental mass deletion.

---

FASE 22 — ACCEPTANCE CRITERIA

Perubahan dianggap berhasil jika:

[ ] Repository berhasil di-clone.

[ ] Struktur repository sudah diaudit.

[ ] Tailscale existing implementation sudah dipahami dan digunakan kembali jika memungkinkan.

[ ] Windows RDP dapat di-enable oleh script.

[ ] NLA tetap enabled.

[ ] TermService otomatis berjalan.

[ ] Tailscale berjalan sebagai service.

[ ] Target dapat memperoleh Tailscale IP.

[ ] RDP workflow tidak menggunakan public IP.

[ ] RDP workflow tidak membutuhkan port forwarding.

[ ] Tidak ada instruksi membuka 3389 ke Internet.

[ ] Firewall tidak membuat RDP publicly exposed.

[ ] Windows App dapat menggunakan Tailscale IP/MagicDNS sebagai endpoint.

[ ] FreeRDP tidak lagi menjadi remote-access client utama.

[ ] AnyDesk tidak lagi menjadi remote-access client utama.

[ ] Chrome Remote Desktop tidak menjadi dependency.

[ ] Setup bersifat idempotent.

[ ] Error handling memadai.

[ ] README diperbarui.

[ ] Legacy functionality didokumentasikan.

[ ] Static/syntax tests dijalankan.

[ ] git diff direview.

[ ] Tidak ada credential/secret yang masuk ke commit.

---

ATURAN PENTING UNTUK AGENT

1. Jangan hanya memberikan rekomendasi. LAKUKAN perubahan pada working copy repository.

2. Jangan berhenti setelah menemukan masalah. Perbaiki masalah tersebut jika berada dalam scope.

3. Jangan mengarang isi repository. Selalu baca file aktual.

4. Jangan menghapus file sebelum memahami dependency-nya.

5. Jangan membuat asumsi bahwa nama file menggambarkan fungsi sebenarnya.

6. Prioritaskan kompatibilitas dengan workflow repository yang sudah ada.

7. Jangan membuat public RDP.

8. Jangan menonaktifkan NLA.

9. Jangan menonaktifkan Windows Firewall.

10. Jangan menambahkan password atau secret ke source code.

11. Jangan membuat persistence tersembunyi.

12. Jangan menginstall software remote-access pihak ketiga yang tidak diperlukan.

13. Gunakan Tailscale official mechanism/service jika memang sudah tersedia.

14. Jika repository sudah mempunyai implementasi Tailscale yang benar, gunakan/reuse daripada membuat implementasi kedua.

15. Jika terdapat konflik antara workflow lama dan workflow baru, workflow baru harus menjadi default.

16. Jangan melakukan force push ke repository upstream.

17. Jangan mengubah git history.

18. Jangan commit kecuali environment/aturan agent memang meminta commit. Jika commit dibuat, gunakan commit message yang jelas.

19. Jangan publish secret.

20. Jika menemukan security vulnerability existing yang berada di luar scope, jangan diam-diam mengabaikannya. Laporkan di final report.

---

FINAL REPORT

Setelah selesai, berikan laporan dalam format:

Summary

Apa yang diubah.

Architecture

Jelaskan arsitektur final.

Files Changed

Daftar file:

- added
- modified
- deprecated
- removed

dengan alasan singkat.

Tailscale

Jelaskan bagaimana Tailscale sekarang digunakan.

RDP

Jelaskan bagaimana Windows RDP sekarang diaktifkan.

Firewall

Jelaskan bagaimana akses RDP dibatasi dan pastikan tidak publicly exposed.

Windows App

Berikan langkah koneksi dari client.

Contoh:

Windows App
→ Add PC
→ 100.x.x.x
→ Windows credentials

Legacy

Jelaskan apa yang terjadi pada FreeRDP, AnyDesk, public-IP workflow, dan CRD.

Security

Jelaskan security improvements.

Testing

Daftar semua test yang dijalankan dan hasilnya.

Pisahkan:

PASS
FAIL
NOT TESTABLE

Remaining Issues

Jelaskan masalah yang masih tersisa.

Recommended Next Steps

Berikan langkah lanjutan jika ada.

---

HASIL AKHIR YANG DIINGINKAN

Workflow akhir harus sesederhana:

PC TARGET
↓
Run setup script as Administrator
↓
Tailscale connected
↓
Windows RDP enabled
↓
Firewall configured safely
↓
Display Tailscale IP
↓
DONE

Kemudian dari PC CLIENT:

Tailscale
↓
same tailnet
↓
Windows App
↓
Add PC
↓
100.x.x.x
↓
Windows credentials
↓
Remote Desktop

Jangan mengubah workflow ini menjadi CRD.

Target akhir adalah:

Tailscale + native Windows RDP + Microsoft Windows App

dengan RDP tetap privat melalui tailnet dan tidak terekspos ke Internet publik.