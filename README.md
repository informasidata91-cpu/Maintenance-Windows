Windows Maintenance Script - Silent Automated Mode
Deskripsi
Skrip ini dirancang untuk melakukan perawatan sistem Windows secara otomatis dan silent.
Menggabungkan beberapa perintah penting untuk memastikan integritas file sistem, kesehatan image Windows, jaringan, dan memori.
Setelah skrip selesai, komputer akan melakukan restart otomatis.
Skrip ini cocok untuk administrator atau pengguna yang ingin melakukan maintenance rutin tanpa interaksi manual.

Fitur Utama
System File Checker (SFC)
Memeriksa dan memperbaiki file sistem Windows yang rusak.

DISM (Deployment Image Servicing and Management) – 3-Step
/CheckHealth – memeriksa apakah image Windows rusak.
/ScanHealth – scan lebih mendalam untuk kerusakan image.
/RestoreHealth – memperbaiki kerusakan image secara otomatis.

Flush DNS
Membersihkan cache DNS untuk memperbaiki masalah konektivitas atau resolusi nama domain.

Reset Winsock
Mereset konfigurasi jaringan Windows untuk menyelesaikan masalah koneksi.

CHKDSK
Memeriksa integritas drive C: dan secara otomatis menjadwalkan perbaikan bila ditemukan masalah.

Memory Diagnostic
Menjadwalkan Windows Memory Diagnostic untuk dijalankan saat restart.

Logging Otomatis
Semua output perintah disimpan di:
C:\MaintenanceLog.txt

Restart Otomatis
Setelah semua langkah selesai, komputer akan restart dalam 30 detik dengan pesan:
Maintenance Windows selesai. Komputer akan restart otomatis.

Cara Penggunaan
Simpan skrip sebagai WindowsMaintenance.ps1.
Jalankan PowerShell sebagai Administrator.
Eksekusi skrip:
.\WindowsMaintenance.ps1
Tunggu proses selesai — skrip akan menampilkan log di layar dan di C:\MaintenanceLog.txt.
Komputer akan otomatis restart untuk menyelesaikan CHKDSK dan Memory Diagnostic.

Catatan Penting
Pastikan PowerShell dijalankan dengan hak administrator, jika tidak beberapa langkah seperti DISM dan CHKDSK akan gagal.
CHKDSK hanya akan dijalankan jika ditemukan kerusakan pada drive.
Windows Memory Diagnostic dijadwalkan untuk ONSTART, sehingga akan berjalan saat komputer berikutnya booting.
Skrip ini tidak menghapus file pengguna.

Disclaimer
Skrip ini dibuat untuk perawatan rutin sistem. Gunakan dengan hati-hati pada komputer yang sedang digunakan untuk pekerjaan penting karena akan restart otomatis.
Backup data penting selalu disarankan sebelum melakukan perawatan sistem.
