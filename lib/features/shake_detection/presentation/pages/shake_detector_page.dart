import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// ============================================================
/// ShakeDetectorPage – Pendeteksi Guncangan Murni (Tahap 1–3)
/// ============================================================
///
/// Menggunakan [accelerometerEvents] (termasuk gravitasi) dan
/// memfilter bias gravitasi secara manual:
///   guncanganMurni = |√(x²+y²+z²) − 9.8|
///
/// Perubahan warna latar berlangsung real-time via [setState]:
///   🔵 Biru  → idle (default)
///   🔴 Merah → guncangan melampaui [shakeThreshold]
///   🟢 Hijau → perangkat kembali tenang setelah guncangan
class ShakeDetectorPage extends StatefulWidget {
  const ShakeDetectorPage({Key? key}) : super(key: key);

  @override
  State<ShakeDetectorPage> createState() => _ShakeDetectorPageState();
}

class _ShakeDetectorPageState extends State<ShakeDetectorPage> {
  // ================================================================
  // KONSTANTA & KONFIGURASI
  // ================================================================

  /// Konstanta gravitasi bumi standar (m/s²) yang selalu hadir
  /// pada pembacaan [accelerometerEvents] karena sensor ini bersifat
  /// total-force (bukan linear acceleration).
  static const double _gravity = 9.8;

  /// Ambang batas guncangan murni (m/s²).
  ///
  /// Setelah bias gravitasi dihilangkan, nilai [_guncanganMurni] harus
  /// melampaui nilai ini agar dianggap sebagai guncangan nyata.
  ///
  /// Panduan penyetelan:
  ///   < 2.0  → terlalu sensitif, geser pelan bisa trigger
  ///   5.0    → ✅ rekomendasi standar (hentakan sedang)
  ///   > 10.0 → hanya mendeteksi guncangan sangat keras
  double shakeThreshold = 5.0;

  /// Debounce: jeda minimum (ms) antara dua guncangan yang diakui.
  /// Mencegah satu gerakan fisik menghasilkan banyak event berturut-turut.
  static const int _debounceDurationMs = 600;

  /// Durasi animasi transisi warna latar belakang (ms).
  static const int _colorTransitionMs = 300;

  // ================================================================
  // STATE VARIABLES
  // ================================================================

  /// Subscription ke stream accelerometer.
  /// WAJIB di-cancel di [dispose()] untuk mencegah memory leak.
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  // ── Nilai mentah sumbu sensor (termasuk gravitasi) ──────────────
  /// Sumbu X: bernilai positif ke kanan, negatif ke kiri.
  double _rawX = 0.0;

  /// Sumbu Y: bernilai positif ke atas, negatif ke bawah.
  double _rawY = 0.0;

  /// Sumbu Z: bernilai positif ke depan layar, negatif ke belakang.
  double _rawZ = 0.0;

  // ── Hasil kalkulasi filter gravitasi ────────────────────────────
  /// Magnitudo vektor percepatan total: √(x²+y²+z²).
  double _totalAcceleration = 0.0;

  /// Guncangan murni setelah gravitasi direduksi: |totalAcceleration−9.8|.
  double _guncanganMurni = 0.0;

  // ── State warna & status ─────────────────────────────────────────
  /// Warna latar belakang layar yang berubah secara dinamis:
  ///   [Colors.blue]  → idle / default
  ///   [Colors.red]   → guncangan melampaui threshold
  ///   [Colors.green] → tenang setelah guncangan
  Color _backgroundColor = Colors.blue;

  /// Label status teks yang ditampilkan di tengah layar.
  String _statusLabel = 'Diam – Siap Mendeteksi';

  /// Timestamp guncangan terakhir untuk logika debounce.
  DateTime _lastShakeTime = DateTime.fromMillisecondsSinceEpoch(0);

  // ================================================================
  // LIFECYCLE
  // ================================================================

  @override
  void initState() {
    super.initState();
    // Mulai mendengarkan sensor segera setelah widget di-mount.
    _initSensor();
  }

  @override
  void dispose() {
    // ✅ KRITIS: Batalkan subscription untuk mencegah memory leak.
    // Tanpa baris ini, callback stream tetap berjalan di background
    // dan mencoba memanggil setState() pada widget yang sudah dibuang.
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  // ================================================================
  // LOGIKA SENSOR & FILTER GRAVITASI
  // ================================================================

  /// Menginisialisasi listener [accelerometerEvents] di dalam [initState].
  ///
  /// Pipeline pemrosesan setiap event:
  ///   1. Baca nilai mentah X, Y, Z (termasuk gravitasi bumi).
  ///   2. Hitung magnitudo total: totalAcceleration = √(x²+y²+z²).
  ///   3. Filter gravitasi: guncanganMurni = |totalAcceleration − 9.8|.
  ///   4. Bandingkan dengan [shakeThreshold] + terapkan debounce.
  ///   5. Perbarui semua state dalam SATU panggilan [setState] (efisien).
  void _initSensor() {
    _accelerometerSubscription = accelerometerEvents.listen(
      (AccelerometerEvent event) {
        // ────────────────────────────────────────────────────────────
        // LANGKAH 1 – Baca nilai mentah tiga sumbu dari sensor
        // ────────────────────────────────────────────────────────────
        final double x = event.x; // sumbu X: kiri (−) / kanan (+)
        final double y = event.y; // sumbu Y: bawah (−) / atas (+)
        final double z = event.z; // sumbu Z: belakang (−) / depan (+)

        // ────────────────────────────────────────────────────────────
        // LANGKAH 2 – Hitung magnitudo vektor percepatan total 3D
        //
        //   totalAcceleration = √(x² + y² + z²)
        //
        // Perangkat diam di meja → totalAcceleration ≈ 9.8 m/s²
        // Perangkat diguncang    → totalAcceleration >> 9.8 m/s²
        // ────────────────────────────────────────────────────────────
        final double totalAcceleration = sqrt(x * x + y * y + z * z);

        // ────────────────────────────────────────────────────────────
        // LANGKAH 3 – Eliminasi bias gravitasi → Guncangan Murni
        //
        //   guncanganMurni = |totalAcceleration − 9.8|
        //
        // Nilai absolut (abs) diperlukan karena pada kondisi tertentu
        // (misal: HP dilempar ke atas) percepatan bisa < 9.8 m/s².
        //
        // Perangkat diam  → guncanganMurni ≈ 0.0 m/s²  (ideal)
        // Diguncang keras → guncanganMurni bisa mencapai 15–25 m/s²
        // ────────────────────────────────────────────────────────────
        final double guncanganMurni = (totalAcceleration - _gravity).abs();

        // ────────────────────────────────────────────────────────────
        // LANGKAH 4 – Threshold check & debounce
        // ────────────────────────────────────────────────────────────
        final DateTime now = DateTime.now();
        // Debounce: abaikan event jika interval sejak guncangan terakhir
        // belum melewati [_debounceDurationMs] milidetik.
        final bool debounceOk =
            now.difference(_lastShakeTime).inMilliseconds > _debounceDurationMs;

        // ────────────────────────────────────────────────────────────
        // LANGKAH 5 – Perbarui SEMUA state dalam satu setState (efisien)
        //
        // Mengumpulkan semua perubahan dalam satu blok setState mencegah
        // Flutter melakukan rebuild ganda yang tidak perlu.
        // ────────────────────────────────────────────────────────────
        setState(() {
          // Simpan nilai mentah sensor untuk ditampilkan di UI
          _rawX = x;
          _rawY = y;
          _rawZ = z;
          _totalAcceleration = totalAcceleration;
          _guncanganMurni = guncanganMurni;

          // ── Logika perubahan warna & status ──────────────────────
          if (guncanganMurni > shakeThreshold && debounceOk) {
            // 🔴 GUNCANGAN TERDETEKSI
            // Nilai murni melampaui threshold dan debounce terpenuhi
            _backgroundColor = Colors.red;
            _statusLabel = '⚡ Guncangan Terdeteksi!';
            _lastShakeTime = now; // reset timer debounce
          } else if (guncanganMurni <= shakeThreshold &&
              _backgroundColor == Colors.red) {
            // 🟢 TENANG SETELAH GUNCANGAN
            // Nilai turun di bawah threshold → transisi ke hijau
            _backgroundColor = Colors.green;
            _statusLabel = '✅ Perangkat Kembali Tenang';
          } else if (_backgroundColor == Colors.green &&
              guncanganMurni <= shakeThreshold) {
            // Tetap hijau selama perangkat tenang — tidak ada perubahan
            // (baris ini eksplisit agar logika terbaca jelas)
          } else {
            // 🔵 STATUS DEFAULT / IDLE
            // Belum ada guncangan sejak aplikasi dibuka
            _backgroundColor = Colors.blue;
            _statusLabel = 'Diam – Siap Mendeteksi';
          }
        });
      },
      // Tangani error stream agar aplikasi tidak crash
      onError: (Object error) {
        debugPrint('[ShakeDetector] Stream error: $error');
      },
      onDone: () {
        debugPrint('[ShakeDetector] Sensor stream closed by system.');
      },
      // Jangan putus koneksi saat ada error sesaat (sensor hiccup)
      cancelOnError: false,
    );
  }

  // ================================================================
  // BUILD – UI RESPONSIF REAL-TIME
  // ================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ── AppBar tetap gelap agar kontras dengan semua warna latar ──
      appBar: AppBar(
        title: const Text(
          'Shake Detector',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 4,
      ),

      // ── Body: AnimatedContainer untuk transisi warna yang halus ──
      body: AnimatedContainer(
        // Durasi transisi warna latar belakang agar tidak mendadak
        duration: const Duration(milliseconds: _colorTransitionMs),
        curve: Curves.easeInOut,
        color: _backgroundColor, // ← berubah real-time via setState
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Ikon status dinamis ────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    key: ValueKey(_backgroundColor),
                    _backgroundColor == Colors.red
                        ? Icons.vibration
                        : _backgroundColor == Colors.green
                            ? Icons.check_circle_outline
                            : Icons.sensors,
                    size: 80,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Label status teks ─────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    key: ValueKey(_statusLabel),
                    _statusLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── PANEL DATA SENSOR ─────────────────────────────
                // Menampilkan nilai koordinat X / Y / Z real-time
                // dengan presisi 2 angka di belakang koma (.toStringAsFixed(2))
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.symmetric(
                      vertical: 20, horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header panel ────────────────────────────
                      const Text(
                        'DATA AKSELEROMETER',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 12),

                      // ── Baris X ─────────────────────────────────
                      _axisRow(
                        axis: 'X',
                        sublabel: 'Kiri / Kanan',
                        value: _rawX,
                        color: const Color(0xFFFF6B6B),
                      ),
                      const SizedBox(height: 8),

                      // ── Baris Y ─────────────────────────────────
                      _axisRow(
                        axis: 'Y',
                        sublabel: 'Atas / Bawah',
                        value: _rawY,
                        color: const Color(0xFF6BCB77),
                      ),
                      const SizedBox(height: 8),

                      // ── Baris Z ─────────────────────────────────
                      _axisRow(
                        axis: 'Z',
                        sublabel: 'Depan / Belakang',
                        value: _rawZ,
                        color: const Color(0xFF4D96FF),
                      ),

                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 12),

                      // ── Total Akselerasi ─────────────────────────
                      _calcRow(
                        label: '√(x²+y²+z²)',
                        value: '${_totalAcceleration.toStringAsFixed(2)} m/s²',
                      ),
                      const SizedBox(height: 6),

                      // ── Guncangan Murni ───────────────────────────
                      _calcRow(
                        label: 'Guncangan Murni',
                        value: '${_guncanganMurni.toStringAsFixed(2)} m/s²',
                        highlight: _guncanganMurni > shakeThreshold,
                      ),
                      const SizedBox(height: 6),

                      // ── Threshold ─────────────────────────────────
                      _calcRow(
                        label: 'Threshold',
                        value: '${shakeThreshold.toStringAsFixed(1)} m/s²',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // HELPER WIDGETS
  // ================================================================

  /// Baris satu sumbu (X/Y/Z) dengan label, sublabel, dan nilai 2 desimal.
  Widget _axisRow({
    required String axis,
    required String sublabel,
    required double value,
    required Color color,
  }) {
    return Row(
      children: [
        // Badge warna sumbu
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
        // Label sumbu
        Expanded(
          child: Text(
            sublabel,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        // Nilai sensor dengan format 2 desimal
        Text(
          '${value.toStringAsFixed(2)} m/s²',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// Baris kalkulasi filter gravitasi (label + nilai, opsional highlight merah).
  Widget _calcRow({
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        Text(
          value,
          style: TextStyle(
            // Warna merah terang jika nilai melampaui threshold
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
