# Windows Maintenance Script - Silent Automated Mode  
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Build Status](https://img.shields.io/badge/Status-Stable-success.svg)](https://github.com/informasidata91-cpu/Maintenance-Windows)
[![Made with PowerShell](https://img.shields.io/badge/Made%20with-PowerShell-5391FE.svg)](https://learn.microsoft.com/en-us/powershell/)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue.svg)
![Version](https://img.shields.io/badge/Version-1.0-lightgrey.svg)
![Maintenance](https://img.shields.io/badge/Auto%20Maintenance-Enabled-green.svg)
________________________________________
## Deskripsi  
Skrip ini dirancang untuk melakukan perawatan sistem Windows secara otomatis dan silent. Menggabungkan beberapa perintah penting untuk memastikan integritas file sistem, kesehatan image Windows, jaringan, dan memori. Setelah skrip selesai, komputer akan melakukan restart otomatis. Skrip ini cocok untuk administrator atau pengguna yang ingin melakukan maintenance rutin tanpa interaksi manual.  
________________________________________
## Fitur Utama  
1.	System File Checker (SFC)  
    Memeriksa dan memperbaiki file sistem Windows yang rusak.  
2.	DISM (Deployment Image Servicing and Management) – 3-Step  
    o	/CheckHealth – memeriksa apakah image Windows rusak.  
    o	/ScanHealth – scan lebih mendalam untuk kerusakan image.  
    o	/RestoreHealth – memperbaiki kerusakan image secara otomatis.  
3.	Flush DNS  
    Membersihkan cache DNS untuk memperbaiki masalah konektivitas atau resolusi nama domain.  
4.	Reset Winsock  
    Mereset konfigurasi jaringan Windows untuk menyelesaikan masalah koneksi.
5.  Disk Cleanup – Drive C  
    Fungsi ini digunakan untuk membersihkan file-file sementara dan sisa sistem pada Drive C: secara otomatis. Tujuannya adalah untuk mengosongkan ruang penyimpanan, meningkatkan performa sistem, serta menjaga kestabilan Windows.
6.	CHKDSK  
    Memeriksa integritas drive C: dan secara otomatis menjadwalkan perbaikan bila ditemukan masalah.  
7.	Memory Diagnostic  
    Menjadwalkan Windows Memory Diagnostic untuk dijalankan saat restart.  
8.	Logging Otomatis  
    Semua output perintah disimpan di:  
    C:\MaintenanceLog.txt  
9.	Restart Otomatis  
    Setelah semua langkah selesai, komputer akan restart dalam 30 detik dengan pesan:  
    "Maintenance Windows selesai. Komputer akan restart otomatis."  
________________________________________
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
## Disclaimer  
Skrip ini dibuat untuk perawatan rutin sistem. Gunakan dengan hati-hati pada komputer yang sedang digunakan untuk pekerjaan penting karena akan restart otomatis. Backup data penting selalu disarankan sebelum melakukan perawatan sistem.  
