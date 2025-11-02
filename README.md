# Floovia
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white) ![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white) ![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black) ![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)

**Floovia** adalah aplikasi pemantauan cuaca komprehensif berbasis Flutter yang berfokus pada wilayah Medan. Aplikasi ini menyediakan data suhu dan curah hujan secara *real-time* dan historis, yang dikumpulkan secara otomatis oleh sistem *backend* di Google Cloud.

Proyek ini dikembangkan sebagai bagian dari inisiatif Program Kreativitas Mahasiswa - Karsa Cipta (PKM-KC).

## 🎯 Tentang Proyek

Tujuan utama Floovia adalah menyediakan informasi cuaca yang akurat dan *real-time* (per jam) bagi masyarakat di Medan. Aplikasi ini memanfaatkan arsitektur modern yang terdiri dari:
1.  **Aplikasi Flutter:** Antarmuka pengguna (*frontend*) yang intuitif dan responsif.
2.  **API Backend:** Sebuah API berbasis **FastAPI (Python)** untuk melayani data dari *database* ke aplikasi.
3.  **Sistem Kolektor Data:** Sebuah **Cloud Function** yang dipicu oleh **Cloud Scheduler** setiap jam untuk mengambil data cuaca terbaru.
4.  **Database:** **Google Firestore** (NoSQL) yang menyimpan data konfigurasi lokasi dan data cuaca *time-series* (historis).

## ✨ Fitur Utama

Aplikasi Floovia dilengkapi dengan berbagai fitur yang dirancang berdasarkan kebutuhan pengguna:

* **Pemantauan Real-time:** Melihat data suhu dan curah hujan terkini berdasarkan lokasi GPS pengguna saat ini.
* **Pencarian Lokasi:** Mencari data cuaca untuk lokasi-lokasi spesifik (kecamatan atau kelurahan) di seluruh Medan.
* **Grafik Historis:** Menganalisis tren cuaca melalui grafik interaktif yang menampilkan riwayat data suhu (grafik garis) dan curah hujan (grafik batang).
* **Visualisasi Peta:** Melihat persebaran data cuaca di berbagai titik pemantauan di Medan melalui tampilan peta.
* **Lokasi Favorit:** Menyimpan dan mengelola daftar lokasi yang sering dipantau untuk akses cepat.
* **Peringatan Dini:** Menerima notifikasi (*push notifications*) jika sistem mendeteksi potensi cuaca ekstrem (misalnya, curah hujan dengan intensitas tinggi).

## 🛠️ Arsitektur & Tumpukan Teknologi (Tech Stack)

Proyek ini dibagi menjadi beberapa komponen utama:

| Komponen | Teknologi | Deskripsi |
| :--- | :--- | :--- |
| **Aplikasi Mobile** | Flutter | *Frontend* aplikasi untuk Android & iOS. |
| **API Backend** | FastAPI (Python) | Melayani permintaan data (*endpoint* API) dari aplikasi Flutter. |
| **Database** | Google Firestore | Database NoSQL untuk menyimpan daftar lokasi dan data cuaca historis. |
| **Kolektor Data** | Cloud Functions | Skrip (Python/Node.js) yang berjalan otomatis untuk mengambil data. |
| **Penjadwal** | Cloud Scheduler | Memicu (trigger) Cloud Function setiap jam. |

### Alur Data (UC-11)
1.  Setiap jam, **Cloud Scheduler** memicu **Cloud Function**.
2.  **Cloud Function** membaca daftar lokasi dari Firestore, lalu mengambil data cuaca (dari API eksternal/sumber data) untuk setiap lokasi.
3.  Data (suhu, curah hujan, timestamp) disimpan ke dalam sub-koleksi di **Firestore**.
4.  Saat pengguna membuka **Aplikasi Flutter**, aplikasi tersebut meminta data ke **FastAPI**.
5.  **FastAPI** membaca data terbaru dari Firestore dan mengirimkannya ke aplikasi untuk ditampilkan.

## 🗄️ Struktur Database (Firestore)

Untuk menjalankan proyek ini, struktur Firestore Anda harus disiapkan sebagai berikut:

**1. Koleksi: `locations`**
* **Dokumen:** `{location_id}` (contoh: `medan_sunggal`)
* **Fields:**
    * `name` (String): "Medan Sunggal"
    * `geo` (Geopoint): Koordinat (lat, long)
    * `last_updated` (Timestamp): Waktu data terakhir diambil
    * `current_temp` (Number): Suhu terakhir (untuk *snapshot*)
    * `current_rainfall` (Number): Curah hujan terakhir (untuk *snapshot*)

**2. Sub-Koleksi: `weather_data`**
* **Path:** `locations/{location_id}/weather_data/{data_id}`
* **Dokumen:** `{data_id}` (bisa *auto-id* atau *timestamp*)
* **Fields:**
    * `timestamp` (Timestamp): Waktu pencatatan data
    * `temperature` (Number): Nilai suhu
    * `rainfall` (Number): Nilai curah hujan

## 🚀 Memulai (Getting Started)

Bagian ini akan memandu Anda untuk menjalankan proyek ini secara lokal.

### Prasyarat

* [Flutter SDK](https://docs.flutter.dev/get-started/install) (Versi 3.x.x)
* [Python](https://www.python.org/downloads/) (Versi 3.9+)
* Akun Google Cloud dengan **Firestore** dan **Cloud Functions** aktif.
* File konfigurasi Firebase:
    * `google-services.json` (untuk Android)
    * `GoogleService-Info.plist` (untuk iOS)
* Kredensial Akun Layanan (Service Account) Google Cloud dalam bentuk file `.json` untuk *backend*.

### 1. Setup Backend (floovia-api)

1.  Clone *repository backend*:
    ```sh
    git clone https://github.com/VinXBoi/PKMKC_FLOOVIA_BACKEND.git
    cd PKMKC_FLOOVIA_BACKEND
    ```
2.  Buat dan aktifkan *virtual environment*:
    ```sh
    python -m venv venv
    source venv/bin/activate  # (Linux/Mac)
    .\venv\Scripts\activate   # (Windows)
    ```
3.  Install dependensi:
    ```sh
    pip install -r requirements.txt
    ```
4.  Letakkan file kredensial Google Cloud Anda (misal: `serviceAccountKey.json`) di direktori *root backend*.
5.  Jalankan server FastAPI:
    ```sh
    uvicorn main:app --reload
    ```
    Server akan berjalan di `http://127.0.0.1:8000`.

### 2. Setup Frontend (Aplikasi Flutter)

1.  Clone *repository* ini (atau jika sudah, navigasi ke folder proyek).
2.  Tempatkan file konfigurasi Firebase Anda:
    * Tempatkan `google-services.json` di dalam `android/app/`.
    * Tempatkan `GoogleService-Info.plist` di dalam `ios/Runner/`.
    * Tempatkan `API_KEY` di dalam `android/app/main/AndroidManifest.cml`.
3.  Install dependensi Flutter:
    ```sh
    flutter pub get
    ```
4.  Pastikan *endpoint* API di dalam kode Flutter (mungkin di `lib/constants.dart` atau `lib/services/api_service.dart`) mengarah ke alamat server FastAPI Anda (misal: `http://127.0.0.1:8000`).
5.  Jalankan aplikasi:
    ```sh
    flutter run
    ```

### 3. Setup Kolektor Data

1.  Buka direktori `cloud_function/` (jika ada di *repo*).
2.  Deploy fungsi tersebut ke Google Cloud Functions.
3.  Buat topik di Cloud Pub/Sub (misal: `run-weather-collector`).
4.  Buat pekerjaan (job) di Cloud Scheduler yang memublikasikan pesan ke topik tersebut setiap jam (`0 * * * *`).

---

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.