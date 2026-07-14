/// ShakeIndicator
///
/// Widget kecil yang menampilkan ikon visual ketika guncangan terdeteksi.
/// Siap dipakai di ShakeDetectorPage pada tahap berikutnya.
import 'package:flutter/material.dart';

class ShakeIndicator extends StatelessWidget {
  final bool isShaking;
  const ShakeIndicator({Key? key, required this.isShaking}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Icon(
      isShaking ? Icons.vibration : Icons.sensors,
      size: 72,
      color: isShaking ? Colors.orange : Colors.white54,
    );
  }
}
