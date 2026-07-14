// ===========================================================================
// FILE   : lib/presentation/pages/shake_detector_page.dart
// AUTHOR : [Nama Mahasiswa]
// DESC   : Pendeteksi guncangan murni menggunakan akselerometer perangkat.
//          Menggabungkan logika sensor (Tahap 1), filter gravitasi (Tahap 2),
//          dan pembaruan UI real-time (Tahap 3) dalam satu file produksi.
//          Perbaikan: throttle UI, SamplingPeriod.ui, anti skipped-frames.
// ===========================================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// [ShakeDetectorPage] - halaman pendeteksi guncangan murni.
///
/// Warna latar berubah real-time:
///   - Colors.blue  : idle (default)
///   - Colors.red   : guncangan terdeteksi
///   - Colors.green : perangkat kembali tenang
class ShakeDetectorPage extends StatefulWidget {
  const ShakeDetectorPage({super.key});

  @override
  State<ShakeDetectorPage> createState() => _ShakeDetectorPageState();
}

class _ShakeDetectorPageState extends State<ShakeDetectorPage> {
  // =========================================================================
  // SECTION 1 - KONSTANTA & KONFIGURASI
  // =========================================================================

  /// Koefisien alpha untuk Low-Pass Filter (LPF) gravitasi adaptif.
  ///
  /// Rumus LPF:  gravity = alpha * gravity + (1 - alpha) * rawAccel
  ///
  /// Nilai alpha mendekati 1.0 = filter lebih lambat merespons rotasi
  /// (gravitasi lebih stabil, guncangan lebih bersih terpisah).
  /// Nilai 0.85 adalah standar yang direkomendasikan Android Developer Guide.
  static const double _kAlpha = 0.85;

  /// Ambang batas guncangan murni (m/s^2) - DAPAT DISESUAIKAN.
  ///
  /// Panduan nilai (setelah LPF - lebih akurat dari fixed 9.8):
  ///   1.5  : sangat sensitif, anggukan kepala bisa trigger
  ///   2.5  : sensitif optimal (hentakan ringan sudah cukup)  <-- DIPAKAI
  ///   4.0  : hentakan sedang
  ///   7.0  : hanya guncangan keras
  double shakeThreshold = 2.5;

  /// Debounce: jeda minimum (ms) antara dua guncangan yang diakui.
  /// Diperkecil ke 300ms agar respons lebih cepat saat mengguncang berulang.
  static const int _kDebounceDurationMs = 300;

  /// Throttle UI: jarak minimum (ms) antar dua panggilan setState.
  /// Diperkecil ke 20ms (=50fps) agar perubahan warna terasa lebih instan.
  static const int _kUiThrottleMs = 20;

  // =========================================================================
  // SECTION 2 - STATE VARIABLES
  // =========================================================================

  /// Subscription ke stream akselerometer.
  /// WAJIB di-cancel di dispose() untuk mencegah memory leak.
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;

  // Nilai mentah sumbu sensor (termasuk gravitasi)
  double _rawX = 0.0; // Sumbu X: kiri (-) / kanan (+)
  double _rawY = 0.0; // Sumbu Y: bawah (-) / atas (+)
  double _rawZ = 0.0; // Sumbu Z: belakang (-) / depan (+)

  // Komponen gravitasi adaptif hasil Low-Pass Filter (LPF).
  // Diperbarui setiap event: gravity = alpha*gravity + (1-alpha)*raw.
  // Dimulai dari 0 agar LPF bisa konvergen ke nilai gravitasi nyata
  // dalam beberapa frame pertama.
  double _gravX = 0.0; // komponen gravitasi sumbu X (hasil LPF)
  double _gravY = 0.0; // komponen gravitasi sumbu Y (hasil LPF)
  double _gravZ = 0.0; // komponen gravitasi sumbu Z (hasil LPF)

  // Hasil kalkulasi filter gravitasi
  double _totalAcceleration = 0.0; // sqrt(x^2 + y^2 + z^2)
  double _guncanganMurni    = 0.0; // magnitudo percepatan linear bersih (tanpa gravitasi)

  // State UI
  Color  _bgColor     = Colors.blue;
  String _statusLabel = 'Diam - Siap Mendeteksi';

  /// Variabel state global warna latar belakang halaman.
  ///
  /// Diikat langsung ke [Scaffold.backgroundColor] agar seluruh layar
  /// merespons perubahan warna secara instan via [setState]:
  ///   - [Colors.blue]  : idle / default
  ///   - [Colors.red]   : guncangan murni > shakeThreshold
  ///   - [Colors.green] : perangkat kembali tenang setelah guncangan
  Color _backgroundColor = Colors.blue;

  /// Timestamp guncangan terakhir untuk debounce.
  DateTime _lastShakeTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Timestamp rebuild UI terakhir untuk throttle.
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  // =========================================================================
  // SECTION 3 - LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();
    _initSensor();
  }

  @override
  void dispose() {
    // WAJIB: cancel subscription untuk mencegah memory leak.
    // Tanpa ini, callback tetap berjalan meski halaman sudah ditutup,
    // menyebabkan "setState() called after dispose()" error.
    _accelerometerSub?.cancel();
    super.dispose();
  }

  // =========================================================================
  // SECTION 4 - LOGIKA SENSOR & ALGORITMA FILTER GRAVITASI
  // =========================================================================

  /// Inisialisasi listener accelerometerEventStream di dalam initState.
  ///
  /// Menggunakan [accelerometerEventStream] (total force, termasuk gravitasi)
  /// bukan [userAccelerometerEventStream] agar algoritma filter gravitasi
  /// dapat dijelaskan secara transparan untuk keperluan akademik.
  void _initSensor() {
    _accelerometerSub = accelerometerEventStream(
      // 8ms per sample (~125Hz) - lebih sering dari sebelumnya (16ms/60Hz).
      // Penting untuk deteksi guncangan singkat yang mungkin terlewat
      // jika interval sampling terlalu panjang.
      samplingPeriod: const Duration(milliseconds: 8),
    ).listen(
      (AccelerometerEvent event) {

        // ------------------------------------------------------------------
        // TAHAP 1: Baca nilai mentah tiga sumbu sensor
        // ------------------------------------------------------------------
        final double x = event.x; // kiri(-) / kanan(+)
        final double y = event.y; // bawah(-) / atas(+)
        final double z = event.z; // belakang(-) / depan(+)

        // ------------------------------------------------------------------
        // TAHAP 2: Low-Pass Filter (LPF) - Isolasi Komponen Gravitasi Adaptif
        //
        // Metode fixed (|total - 9.8|) tidak akurat saat HP miring karena
        // komponen gravitasi terdistribusi ke ketiga sumbu dengan proporsi
        // yang berubah sesuai orientasi perangkat.
        //
        // LPF memperkirakan komponen gravitasi di tiap sumbu secara adaptif:
        //   gravity_i = alpha * gravity_i + (1 - alpha) * raw_i
        //
        // - Saat diam: gravity konvergen ke nilai gravitasi sumbu tersebut.
        // - Saat diguncang: raw_i berubah cepat, gravity tidak bisa mengikuti
        //   (karena alpha=0.85 membuat filter 'lambat') -> selisih besar.
        // ------------------------------------------------------------------
        _gravX = _kAlpha * _gravX + (1 - _kAlpha) * x;
        _gravY = _kAlpha * _gravY + (1 - _kAlpha) * y;
        _gravZ = _kAlpha * _gravZ + (1 - _kAlpha) * z;

        // ------------------------------------------------------------------
        // TAHAP 3: Hitung Percepatan Linear Murni (tanpa gravitasi)
        //
        // Percepatan linear = raw - estimasi_gravitasi (per sumbu)
        //   linX = x - gravX
        //   linY = y - gravY
        //   linZ = z - gravZ
        //
        // Lalu hitung magnitudonya:
        //   guncanganMurni = sqrt(linX^2 + linY^2 + linZ^2)
        //
        // Ini jauh lebih akurat dari |sqrt(x2+y2+z2) - 9.8| karena:
        //   - Gravitasi dipisahkan PER SUMBU (bukan hanya magnitudonya)
        //   - Bekerja benar di semua orientasi HP (portrait/landscape/terbalik)
        //   - Noise sensor teredam oleh filter rekursif
        // ------------------------------------------------------------------
        final double linX = x - _gravX;
        final double linY = y - _gravY;
        final double linZ = z - _gravZ;

        // Magnitudo total percepatan raw (untuk ditampilkan di UI panel)
        final double totalAcceleration = sqrt(x * x + y * y + z * z);

        // Guncangan murni: magnitudo vektor percepatan linear bersih
        //   Perangkat diam/miring -> linX,Y,Z ~= 0 -> guncanganMurni ~= 0
        //   Perangkat diguncang   -> linX,Y,Z besar -> guncanganMurni besar
        final double guncanganMurni = sqrt(linX * linX + linY * linY + linZ * linZ);

        // ------------------------------------------------------------------
        // TAHAP 4: Threshold check + Debounce
        // ------------------------------------------------------------------
        final DateTime now = DateTime.now();

        // Debounce: abaikan event jika guncangan terakhir belum cukup lama
        final bool debounceOk =
            now.difference(_lastShakeTime).inMilliseconds > _kDebounceDurationMs;

        // ------------------------------------------------------------------
        // TAHAP 5: Hitung state baru, lalu update UI dengan throttle
        //
        // Logika deteksi berjalan di SETIAP event (akurasi terjaga),
        // tetapi setState() hanya dipanggil setiap _kUiThrottleMs ms.
        // Ini adalah solusi untuk "Skipped frames" di logcat.
        // ------------------------------------------------------------------

        // Hitung warna dan label baru SEBELUM masuk blok setState
        Color  newColor  = _bgColor;
        String newLabel  = _statusLabel;

        if (guncanganMurni > shakeThreshold && debounceOk) {
          // GUNCANGAN TERDETEKSI: warna merah
          newColor  = Colors.red;
          newLabel  = 'Guncangan Terdeteksi!';
          // Update debounce timestamp di luar setState (thread-safe untuk read)
          _lastShakeTime = now;

        } else if (guncanganMurni <= shakeThreshold && _bgColor == Colors.red) {
          // KEMBALI TENANG setelah guncangan: warna hijau
          newColor  = Colors.green;
          newLabel  = 'Perangkat Kembali Tenang';

        } else if (_bgColor == Colors.green && guncanganMurni <= shakeThreshold) {
          // TETAP TENANG: pertahankan hijau, tidak ada perubahan

        } else if (guncanganMurni > shakeThreshold) {
          // MASIH DIGUNCANG tapi debounce memblokir pengenalan baru.
          // Pertahankan warna saat ini agar tidak balik ke biru
          // di tengah guncangan yang masih berlangsung.
          // newColor sudah = _bgColor (diinisialisasi di atas), tidak perlu diubah.

        } else {
          // IDLE / DEFAULT: warna biru.
          // Hanya masuk sini jika magnitude RENDAH dan bukan sedang recovery.
          newColor  = Colors.blue;
          newLabel  = 'Diam - Siap Mendeteksi';
        }

        // THROTTLE GATE: lewati rebuild jika belum waktunya
        final bool uiReady =
            now.difference(_lastUiUpdate).inMilliseconds >= _kUiThrottleMs;
        if (!uiReady) return; // skip setState, hemat CPU

        // Satu blok setState() = satu frame rebuild (efisien)
        setState(() {
          _lastUiUpdate      = now;
          _rawX              = x;
          _rawY              = y;
          _rawZ              = z;
          _totalAcceleration = totalAcceleration;
          _guncanganMurni    = guncanganMurni;
          _bgColor           = newColor;
          _statusLabel       = newLabel;

          // Perbarui _backgroundColor agar Scaffold.backgroundColor
          // ikut berubah bersama seluruh state warna di atas.
          // Ini adalah binding point antara logika sensor dan UI layar penuh.
          _backgroundColor   = newColor;
        });
      },

      onError: (Object error) {
        debugPrint('[ShakeDetector] Sensor error: $error');
      },
      onDone: () {
        debugPrint('[ShakeDetector] Sensor stream closed.');
      },
      cancelOnError: false,
    );
  }

  // =========================================================================
  // SECTION 5 - BUILD (UI REAL-TIME)
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // _backgroundColor diikat langsung ke Scaffold agar SELURUH layar
      // (bukan hanya widget di dalamnya) merespons perubahan warna.
      // Ini adalah root dari perubahan warna real-time seluruh halaman.
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Shake Detector',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 4,
      ),
      // AnimatedContainer: menginterpolasi _bgColor lama ke baru selama 300ms.
      // Memberikan transisi warna yang halus tanpa kode animasi manual.
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        color: _bgColor, // berubah otomatis setiap setState dipanggil
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ikon status berubah sesuai kondisi sensor
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      key: ValueKey(_bgColor),
                      _bgColor == Colors.red
                          ? Icons.vibration
                          : _bgColor == Colors.green
                              ? Icons.check_circle_outline
                              : Icons.sensors,
                      size: 84,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Label status teks
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      key: ValueKey(_statusLabel),
                      _statusLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Panel data akselerometer
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DATA AKSELEROMETER  (m/s2)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                            letterSpacing: 2.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Divider(color: Colors.white24, height: 1),
                        const SizedBox(height: 14),

                        // Nilai X dengan format 2 angka desimal
                        _axisRow(
                          axis: 'X', sublabel: 'Kiri / Kanan',
                          value: _rawX,
                          badgeColor: const Color(0xFFFF6B6B),
                        ),
                        const SizedBox(height: 10),

                        // Nilai Y dengan format 2 angka desimal
                        _axisRow(
                          axis: 'Y', sublabel: 'Atas / Bawah',
                          value: _rawY,
                          badgeColor: const Color(0xFF6BCB77),
                        ),
                        const SizedBox(height: 10),

                        // Nilai Z dengan format 2 angka desimal
                        _axisRow(
                          axis: 'Z', sublabel: 'Depan / Belakang',
                          value: _rawZ,
                          badgeColor: const Color(0xFF4D96FF),
                        ),

                        const SizedBox(height: 18),
                        const Divider(color: Colors.white24, height: 1),
                        const SizedBox(height: 14),

                        // sqrt(x^2+y^2+z^2) - magnitudo total akselerometer raw
                        _calcRow(
                          label: 'Magnitudo sqrt(x2+y2+z2)',
                          value: '${_totalAcceleration.toStringAsFixed(2)} m/s2',
                        ),
                        const SizedBox(height: 8),

                        // Guncangan murni dari LPF (merah jika > threshold)
                        _calcRow(
                          label: 'Guncangan Murni (LPF)',
                          value: '${_guncanganMurni.toStringAsFixed(2)} m/s2',
                          highlight: _guncanganMurni > shakeThreshold,
                        ),
                        const SizedBox(height: 8),

                        // Nilai threshold saat ini
                        _calcRow(
                          label: 'Threshold',
                          value: '${shakeThreshold.toStringAsFixed(1)} m/s2',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // SECTION 6 - HELPER WIDGETS
  // =========================================================================

  /// Baris tampilan satu sumbu sensor.
  /// Nilai ditampilkan dengan toStringAsFixed(2) - 2 angka di belakang koma.
  Widget _axisRow({
    required String axis,
    required String sublabel,
    required double value,
    required Color badgeColor,
  }) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            axis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            sublabel,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        // toStringAsFixed(2): format wajib 2 angka di belakang koma
        Text(
          value.toStringAsFixed(2),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// Baris hasil kalkulasi filter gravitasi.
  /// [highlight] = true: warna merah sebagai sinyal melampaui threshold.
  Widget _calcRow({
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: highlight ? const Color(0xFFFF6B6B) : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
