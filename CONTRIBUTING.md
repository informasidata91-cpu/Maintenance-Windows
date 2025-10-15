# Panduan Kontribusi ｜ Contributing Guidelines

---

## 🇮🇩 Bahasa Indonesia

Terima kasih telah tertarik untuk berkontribusi pada proyek **Maintenance-Windows**! Panduan ini membantu kamu agar proses kontribusi berjalan lancar dan sesuai standar proyek.  

---

### 🚀 Cara Berkontribusi

1. **Fork** repositori ini ke akun GitHub kamu.  
2. Clone ke lokal:
   ```bash
   git clone https://github.com/namamu/Maintenance-Windows.git
   cd Maintenance-Windows
   ```
3. Buat branch baru untuk perubahanmu:
   ```bash
   git checkout -b fitur-nama-anda
   ```
4. Lakukan perubahan, lalu commit dengan pesan yang jelas:
   ```bash
   git commit -m "feat: menambahkan fungsi pembersihan log otomatis"
   ```
5. Push branch:
   ```bash
   git push origin fitur-nama-anda
   ```
6. Buat **Pull Request (PR)** ke branch `main`.

---

### 📋 Aturan Penulisan Kode

- Gunakan **PowerShell (.ps1)** atau **Batch (.bat)** sesuai standar proyek.  
- Tambahkan komentar pada bagian skrip yang penting atau kompleks.  
- Hindari langkah destruktif tanpa konfirmasi (contoh: penghapusan otomatis).  
- Gunakan pesan commit dengan format:
  ```
  feat: menambahkan fitur baru
  fix: memperbaiki bug
  docs: memperbarui dokumentasi
  ```

---

### 🧪 Pengujian

- Jalankan skrip di lingkungan uji sebelum diajukan.
- Pastikan tidak ada error atau efek negatif pada sistem.
- Simpan hasil log di file `MaintenanceLog.txt` atau sesuai standar.

---

### 💬 Pelaporan Masalah

Jika menemukan bug atau saran perbaikan:
1. Buat **Issue** baru di GitHub.
2. Jelaskan langkah-langkah untuk mereproduksi masalah.
3. Gunakan label: `bug`, `enhancement`, atau `question`.

---

### 🧾 Lisensi

Dengan mengirimkan kontribusi, kamu menyetujui bahwa kontribusi tersebut berada di bawah lisensi proyek ini (**MIT License**). Lihat file [LICENSE](./LICENSE) untuk detailnya.

---

## 🇬🇧 English Version

Thank you for your interest in contributing to **Maintenance-Windows**! This guide will help ensure your contributions are consistent and easy to integrate.  

---

### 🚀 How to Contribute

1. **Fork** this repository to your own GitHub account.  
2. Clone it locally:
   ```bash
   git clone https://github.com/yourname/Maintenance-Windows.git
   cd Maintenance-Windows
   ```
3. Create a new branch for your feature or fix:
   ```bash
   git checkout -b feature-yourname
   ```
4. Make your changes and commit with a clear message:
   ```bash
   git commit -m "feat: add automatic log cleanup"
   ```
5. Push your branch:
   ```bash
   git push origin feature-yourname
   ```
6. Open a **Pull Request (PR)** to the `main` branch.

---

### 📋 Code Guidelines

- Use **PowerShell (.ps1)** or **Batch (.bat)** scripts following the project’s structure.  
- Add comments to explain complex logic or administrative commands.  
- Avoid destructive actions without user confirmation.  
- Use clear commit message format:
  ```
  feat: add new feature
  fix: fix an existing issue
  docs: update documentation
  ```

---

### 🧪 Testing

- Always test your script in a safe environment before submitting.  
- Ensure no errors occur and no harmful effects on the system.  
- Log outputs should be saved to `MaintenanceLog.txt` or other defined files.

---

### 💬 Reporting Issues

If you find a bug or have improvement suggestions:
1. Open a **new Issue** on GitHub.
2. Include clear reproduction steps.
3. Use labels such as `bug`, `enhancement`, or `question`.

---

### 🧾 License

By submitting your contribution, you agree that it will be licensed under this project’s **MIT License**. See the [LICENSE](./LICENSE) file for more details.

---

🙏 Terima kasih telah berkontribusi! | Thank you for contributing!  
