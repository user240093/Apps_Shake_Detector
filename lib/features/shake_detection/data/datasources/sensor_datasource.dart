import 'package:sensors_plus/sensors_plus.dart';

/// SensorDatasource
///
/// Bertanggung jawab menyediakan stream data mentah dari hardware sensor.
/// Menggunakan [userAccelerometerEvents] dari package sensors_plus yang
/// sudah mengeliminasi komponen gravitasi konstan bumi (~9.8 m/s²).
abstract class SensorDatasource {
  /// Stream data akselerometer bebas gravitasi (linear acceleration).
  Stream<UserAccelerometerEvent> get accelerometerStream;
}
