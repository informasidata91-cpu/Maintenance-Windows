# Windows Maintenance Script - Silent Automated Mode  
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Build Status](https://img.shields.io/badge/Status-Stable-success.svg)](https://github.com/informasidata91-cpu/Maintenance-Windows)
[![Made with PowerShell | CMD](https://img.shields.io/badge/Made%20with-PowerShell%20%7C%20CMD-5391FE.svg?logo=powershell&logoColor=white)](https://learn.microsoft.com/en-us/powershell/) 
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue.svg)
![Version](https://img.shields.io/badge/Version-2.0.0.0-lightgrey.svg)
![Maintenance](https://img.shields.io/badge/Auto%20Maintenance-Enabled-green.svg)
________________________________________
## Deskripsi  
Skrip ini melakukan perawatan sistem Windows secara otomatis dan silent. Mencakup SFC, DISM 3-langkah, pembersihan log CBS/DISM, reset komponen Windows Update, perbaikan jaringan (Flush DNS \& Winsock reset), cleanup komprehensif termasuk StartComponentCleanup dan ekstra cache/log, optimasi storage (Defrag/TRIM), CHKDSK online dengan penjadwalan perbaikan saat reboot jika diperlukan, serta Windows Memory Diagnostic. Skrip melakukan auto-elevate ke Administrator, menyetel ExecutionPolicy scope proses ke Bypass, dan mencatat transcript ke C:\MaintenanceLog.txt. 
________________________________________
## Fitur Utama  

1. DISM (3 langkah)
    - /CheckHealth, /ScanHealth, /RestoreHealth untuk memeriksa dan memperbaiki image Windows.
    - Menyediakan ringkasan tail dism.log untuk visibilitas cepat hasil DISM.
2. System File Checker (SFC)
    - Menjalankan sfc /scannow dan menyimpan output ke berkas log sementara di %TEMP%, dengan path dicatat pada output.
3. Reset Windows Update components
    - Menghentikan layanan BITS, wuauserv, cryptsvc, msiserver.
    - Merename SoftwareDistribution dan catroot2 dengan suffix timestamp, lalu menyalakan kembali layanan.
4. Network fixes
    - Flush DNS cache dan netsh winsock reset.
5. Disk cleanup
    - Menghapus folder TEMP (user dan system), menjalankan DISM /StartComponentCleanup, dan Clear-RecycleBin.
6. Extra cleanup
    - Menghapus folder cache: SoftwareDistribution\Download, DeliveryOptimization, Logs\CBS, Logs\DISM, Prefetch.
    - Menghapus Windows.old; jika terkunci, fallback ke takeown/icacls kemudian rmdir.
7. Optimasi storage
    - Menganalisis volume tetap, mendeteksi SSD vs HDD, menjalankan ReTrim untuk SSD atau Defrag untuk HDD.
8. CHKDSK
    - Menjalankan chkdsk /scan dan menginterpretasi exit code.
    - Jika perlu, menjadwalkan perbaikan pada reboot berikutnya menggunakan /spotfix atau /F /R.
9. Windows Memory Diagnostic
    - Menjadwalkan atau menjalankan segera melalui mdsched.exe dengan elevasi; hasil dapat dilihat di Event Viewer.
10. Logging otomatis
    - Start-Transcript ke C:\MaintenanceLog.txt, menutup transcript dengan ringkasan durasi eksekusi.
11. Restart otomatis
    - Menjadwalkan restart menggunakan shutdown.exe (default 30 detik, dapat dibatalkan), dengan fallback Restart-Computer bila perlu.  

____________________________________  
## Parameter

Tersedia switch parameter untuk mengontrol langkah:

- -Silent: Nonaktifkan prompt informasi awal.
- -SkipDISM: Lewati langkah DISM 3-langkah.
- -SkipSFC: Lewati SFC.
- -SkipWUReset: Lewati reset komponen Windows Update.
- -SkipCleanup: Lewati cleanup umum (TEMP, StartComponentCleanup, Recycle Bin).
- -SkipDefrag: Lewati Optimize-Drives (Defrag/TRIM).
- -SkipChkdsk: Lewati CHKDSK.
- -SkipNetworkFix: Lewati Flush DNS dan Winsock reset.
- -SkipMemoryDiag: Lewati Windows Memory Diagnostic.
- -SkipExtraCleanup: Lewati cleanup ekstra (Download, DeliveryOptimization, CBS/DISM logs, Prefetch, Windows.old).
- -NoRestart: Menonaktifkan restart otomatis di akhir.
- -ForceAutoRestart: Memaksa restart otomatis tanpa prompt.

Catatan:

- Skrip meneruskan parameter saat auto-elevate sehingga perilaku konsisten setelah relaunch.  
____________________________________
## Cara Penggunaan  
1.	Simpan skrip sebagai Maintenance.ps1.  
2.	Jalankan PowerShell sebagai Administrator.  
3.	Eksekusi skrip:  
    ```powershell
  	Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Invoke-WebRequest "https://raw.githubusercontent.com/informasidata91-cpu/Maintenance-Windows/main/Maintenance.ps1" -OutFile "Maintenance.ps1"  
    ./Maintenance.ps1
    ```
    Atau
    ```powershell
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest 'https://raw.githubusercontent.com/informasidata91-cpu/Maintenance-Windows/main/Maintenance.ps1' -OutFile 'Maintenance.ps1'; ./Maintenance.ps1"
    ```       
4.	Tunggu proses selesai — skrip akan menampilkan log di layar dan di C:\MaintenanceLog.txt.  
5.	Komputer akan otomatis restart untuk menyelesaikan CHKDSK dan Memory Diagnostic.  
________________________________________  
## Urutan Eksekusi

- Ensure-Admin (auto-elevate + ExecutionPolicy scope proses Bypass)
- Logging: Start-Transcript
- Informasi awal (kecuali -Silent)
- SFC
- DISM 3-step
- Cleanup CBS/DISM logs (opsi backup dan rotasi/hapus log lama)
- Reset Windows Update
- Network Fix
- Disk Cleanup
- Extra Cleanup
- Optimize Drives
- CHKDSK (scan online dan jadwalkan jika perlu)
- Memory Diagnostic
- Ringkasan maintenance
- Restart otomatis (kecuali -NoRestart)  
________________________________________  
## Catatan Penting  
1. Pastikan PowerShell dijalankan dengan hak administrator, jika tidak beberapa langkah seperti DISM dan CHKDSK akan gagal.  
2. CHKDSK hanya akan dijalankan jika ditemukan kerusakan pada drive.  
3. Windows Memory Diagnostic dijadwalkan untuk ONSTART, sehingga akan berjalan saat komputer berikutnya booting.  
4. Skrip ini tidak menghapus file pengguna.  
________________________________________
## 🧩 Penjelasan File: Maintenance.exe
**Maintenance.exe** adalah versi kompilasi dari skrip otomatisasi pemeliharaan Windows (Maintenance.ps1). File ini dibuat agar pengguna dapat menjalankan seluruh proses perawatan sistem tanpa perlu membuka PowerShell atau Command Prompt secara manual.  

### 🎯 Fungsi Utama  
- Menjalankan berbagai tugas pemeliharaan sistem Windows secara otomatis, termasuk:  
  - Pemeriksaan integritas file sistem menggunakan SFC.  
  - Pemulihan image sistem menggunakan DISM.  
  - Pembersihan cache DNS dan reset konfigurasi jaringan.  
  - Penghapusan file sementara dan pembersihan sistem.  
  - Pemeriksaan memori (RAM) dan restart otomatis setelah proses selesai.  
- Menyediakan antarmuka eksekusi tunggal (single-click executable) agar mudah digunakan oleh pengguna non-teknis.  

### 🧾 Catatan Tambahan  
- File **Maintenance.exe** dapat dijalankan langsung dengan klik ganda atau melalui Task Scheduler untuk otomatisasi berkala.  
- Pastikan menjalankannya dengan hak **Administrator** agar seluruh perintah sistem dapat dieksekusi tanpa hambatan.  
- Apabila terjadi kesalahan seperti “_The system cannot find the file specified_”, pastikan seluruh file pendukung (.bat, .ps1, atau folder Resources) berada di direktori yang sama.  

### 🧰 Kompilasi & Sumber
**Maintenance.exe** dihasilkan dari konversi skrip PowerShell menggunakan alat seperti:  
- PS2EXE (ps2exe.ps1)  
- Bat To Exe Converter  
- atau build pipeline PowerShell bawaan Windows.  

Tujuan kompilasi ini adalah menjaga kemudahan distribusi, keamanan, dan mencegah modifikasi skrip yang tidak diinginkan.

### 🛡️ Verifikasi Keamanan File
>
> Saat pengguna mengunduh **Maintenance.exe**, sistem keamanan pada browser atau Windows mungkin akan menampilkan peringatan seperti berikut:
>
> 1. “Windows protected your PC”  
> 2. “This app can’t be verified”  
> 3. “This type of file can harm your computer”  
> 4. “This app can’t run on your PC”  
> 5. “Unknown publisher – The publisher of this app couldn’t be verified”
>
> Pesan-pesan tersebut **tidak berarti file berbahaya**, melainkan karena **file belum ditandatangani (unsigned)** menggunakan **sertifikat digital resmi dari Otoritas Sertifikat (Certificate Authority/CA)**.

#### 🧾 Mengapa Muncul Peringatan?
Windows dan browser modern seperti Microsoft Edge, Google Chrome, atau Mozilla Firefox secara otomatis memeriksa tanda tangan digital pada file eksekusi (*.exe*) untuk memastikan:
- Identitas penerbit dapat diverifikasi.  
- File tidak diubah setelah ditandatangani.  

Apabila file tidak memiliki tanda tangan digital yang valid, sistem tidak dapat mengonfirmasi penerbitnya, sehingga muncul peringatan sebagai tindakan pencegahan keamanan.

#### 🧩 Cara Tetap Mengunduh File
Jika Anda mengunduh file **Maintenance.exe** dan menemui peringatan, ikuti langkah-langkah berikut sesuai browser yang digunakan:

**🔹 Microsoft Edge:**
1. Saat muncul pesan *“Maintenance.exe was blocked because it could harm your device”*, klik **"..." (titik tiga)** di sebelah kanan pesan.  
2. Pilih **"Keep"** → kemudian pilih **"Show more"** → **"Keep anyway"**.  
3. Setelah file tersimpan, klik kanan pada file → **Properties** → centang **"Unblock"** (jika ada), lalu jalankan.

**🔹 Google Chrome:**
1. Jika muncul pesan *“Maintenance.exe may be dangerous”*, klik **panah kecil (˅)** di sebelah kanan pesan.  
2. Pilih **"Keep"** → kemudian **"Keep anyway"** untuk tetap menyimpan file.  

**🔹 Firefox:**
1. Jika muncul pesan *“This file may harm your computer”*, klik **"Allow download"** untuk melanjutkan.  

**🔹 Saat menjalankan di Windows:**
1. Jika muncul kotak dialog *Windows protected your PC*, klik **“More info”**.  
2. Lalu pilih **“Run anyway”** untuk menjalankan program.

#### 🚫 Jika File Dianggap Malware atau Diblokir Antivirus
Beberapa antivirus atau fitur keamanan Windows (seperti Defender, SmartScreen, atau sistem reputasi file berbasis cloud) dapat salah mendeteksi file yang belum ditandatangani sebagai:
- “Trojan”  
- “Suspicious file”  
- “Potentially unwanted program (PUP)”  
- “Heuristic detection”  
- atau menandainya sebagai *malware* tanpa alasan yang jelas.

Hal ini merupakan **deteksi keliru (false positive)** yang umum terjadi pada file yang melakukan **perubahan terhadap sistem** seperti:
- Membersihkan file sementara (*temporary files*), log, dan cache sistem.  
- Melakukan optimasi atau reset konfigurasi tertentu.  
- Menjalankan perintah administratif (*system maintenance*, *cleanup*, atau *service restart*).  

Tindakan tersebut **bukan aktivitas berbahaya**, namun karena melibatkan perubahan sistem, beberapa antivirus dapat menganggapnya sebagai potensi ancaman. Jika Anda mendapatkan peringatan seperti itu:
1. Pilih opsi **“Allow”**, **“Allow on device”**, atau **“Restore”** dari karantina antivirus.  
2. Tambahkan file **Maintenance.exe** ke daftar **exceptions / exclusions** pada antivirus.  
3. Pastikan file tersebut diunduh **hanya dari repositori resmi ini** untuk menjamin keasliannya.  

Tindakan *Allow* atau *Restore* dalam konteks ini **tidak berbahaya**, karena file ini **tidak mengandung virus, trojan, atau malware**, melainkan menjalankan fungsi *system cleaning* dan *maintenance* sebagaimana yang dijelaskan dalam proyek ini.    

#### ✅ Apakah Aman Dijalankan?
Ya, **file Maintenance.exe aman dijalankan**, selama Anda mengunduhnya langsung dari repositori resmi ini (**Data Informasi™ – Maintenance Windows**). File ini tidak mengandung kode berbahaya, malware, atau aktivitas mencurigakan. Peringatan SmartScreen dapat diabaikan **karena penyebabnya hanya absennya sertifikat digital**, bukan karena ada ancaman nyata.

#### 🪪 Mengapa Tidak Ditandatangani Sertifikat Resmi?
Untuk memperoleh sertifikat digital resmi dari CA terpercaya (seperti **DigiCert**, **Sectigo**, atau **GlobalSign**), pengembang harus:
- Melalui proses verifikasi identitas organisasi atau individu yang ketat.  
- Menyediakan dokumen hukum dan bukti kepemilikan domain.  
- Membayar biaya tahunan yang tidak sedikit (umumnya mulai dari ratusan hingga ribuan dolar per tahun).

Karena proses dan biayanya tidak sederhana, banyak proyek **independen, non-komersial, atau open-source** memilih untuk tidak menggunakan tanda tangan digital resmi, selama distribusi file dilakukan melalui **sumber resmi yang tepercaya**.

> 💡 **Kesimpulan:**  
> File **Maintenance.exe** aman digunakan apabila diunduh langsung dari repositori resmi ini. Peringatan SmartScreen hanyalah bagian dari mekanisme perlindungan standar Windows terhadap file tanpa sertifikat digital, **bukan indikasi bahwa file berbahaya**.
---  
## Unduh Rilis (Releases)  
Halaman Releases adalah pusat distribusi versi aplikasi ini yang dikemas berdasarkan tag Git; di sana Anda dapat membaca ringkasan perubahan setiap versi dan mengunduh aset siap pakai (mis. .exe, .zip) tanpa perlu membangun dari sumber. Rilis yang diberi label “Latest” menandai versi terbaru yang direkomendasikan, sementara beberapa entri dapat ditandai sebagai “Pre-release” jika masih tahap uji. Keamanan dan integritas asal rilis ditingkatkan dengan penanda “Verified” pada komit/tag yang ditandatangani secara kriptografis, sehingga Anda dapat memverifikasi sumber sebelum mengunduh. Untuk selalu menuju versi terbaru, gunakan tautan berikut:  
[![GitHub Releases](https://img.shields.io/github/v/release/informasidata91-cpu/Maintenance-Windows?display_name=release&sort=semver&color=blue&logo=github)](https://github.com/informasidata91-cpu/Maintenance-Windows/releases/latest) .  

--- 
## Disclaimer  
Skrip ini dibuat untuk perawatan rutin. Gunakan dengan hati-hati pada komputer yang sedang digunakan untuk pekerjaan penting karena akan restart otomatis. Backup data penting selalu disarankan sebelum melakukan perawatan sistem.  
