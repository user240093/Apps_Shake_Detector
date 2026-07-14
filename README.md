# Shake Detector App 📱✨

Aplikasi Flutter sederhana yang dirancang untuk mendeteksi guncangan atau goyangan pada perangkat *mobile* menggunakan sensor *Accelerometer*. Aplikasi ini dibuat untuk memenuhi modul latihan praktikum akses sensor spasial, di mana warna latar belakang layar akan berubah secara dinamis mengikuti kondisi pergerakan perangkat.

---

## 🚀 Fitur Utama
* **Real-Time Sensor Detection**: Membaca perubahan percepatan perangkat secara instan pada tiga sumbu koordinat (X, Y, dan Z).
* **Dynamic Background Color**: Mengubah warna layar secara dinamis berdasarkan ambang batas guncangan (Default: Biru, Merah saat digoyang, dan Hijau saat perangkat kembali tenang).
* **Metrics Dashboard**: Menampilkan nilai koordinat sensor pada layar secara rapi dengan pembatasan format dua angka di belakang koma (`toStringAsFixed(2)`) agar mudah dipantau.
* **Safe Memory Management**: Implementasi penutupan aliran data sensor (*stream subscription*) secara berkala untuk mencegah terjadinya kebocoran memori (*memory leaks*).

---

## 🛠️ Tech Stack & Dependensi
* **Framework:** Flutter SDK
* **Sensor Package:** `sensors_plus: ^6.0.1` 
* **Target Platform:** Android & Web Browser

---

## 🎛️ Logika Deteksi Pergerakan (Sesuai Modul)
Aplikasi ini mendengarkan aliran data dari `accelerometerEvents`.Perubahan warna komponen UI diatur menggunakan pengkondisian (*conditional logic*) berbasis nilai ambang batas percepatan pada sumbu koordinat perangkat:

* **Kondisi Awal**: Warna default layar diinisialisasi sebagai Biru (`Colors.blue`).
* **Kondisi Digoyang**: Jika entakan guncangan melewati batas threshold yang ditentukan, warna state berubah menjadi Merah (`Colors.red`).
* **Kondisi Tenang**: Jika perangkat tidak menerima guncangan, warna otomatis dialihkan menjadi Hijau (`Colors.green`).

---

## 💻 Cara Menjalankan Proyek Secara Lokal

1. Kloning repository ini ke penyimpanan lokal laptop Anda:
   ```bash
   git clone [https://github.com/user240093/Apps_Shake_Detector.git](https://github.com/user240093/Apps_Shake_Detector.git)