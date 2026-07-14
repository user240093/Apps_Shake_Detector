// ===========================================================================
// FILE : lib/main.dart
// DESC : Entry point aplikasi Shake Detector.
//        Menginisialisasi Flutter engine dan menjalankan root widget.
// ===========================================================================

import 'package:flutter/material.dart';

// Import halaman utama dari layer presentation
import 'presentation/pages/shake_detector_page.dart';

/// Entry point aplikasi Flutter.
///
/// [WidgetsFlutterBinding.ensureInitialized()] dipanggil terlebih dahulu
/// untuk memastikan engine Flutter sudah siap sebelum plugin sensor (yang
/// merupakan platform channel) diakses oleh widget turunan.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShakeDetectorApp());
}

/// Root widget stateless yang mendefinisikan tema global aplikasi.
class ShakeDetectorApp extends StatelessWidget {
  const ShakeDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shake Detector',
      debugShowCheckedModeBanner: false, // hilangkan banner "DEBUG"
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // Seluruh logika sensor dan UI ada di ShakeDetectorPage
      home: const ShakeDetectorPage(),
    );
  }
}
