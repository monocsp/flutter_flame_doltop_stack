import 'dart:async';

import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

/// Microphone service with dynamic ambient calibration and sustained detection.
///
/// Instead of a fixed 50 dB baseline, the service measures the ambient noise
/// level during a calibration window and sets the threshold dynamically.
/// A blow is only registered after [_sustainedTicks] consecutive readings
/// above the threshold (~240 ms at default polling rate) to avoid jitter.
class MicService {
  static const double _ambientOffsetDb = 10.0;
  static const double _breathRangeDb = 18.0;
  static const int _sustainedTicks = 2;

  final StreamController<double> _blowStrengthController =
      StreamController<double>.broadcast();

  NoiseMeter? _noiseMeter;
  StreamSubscription<NoiseReading>? _subscription;
  bool _isDisposed = false;

  // Calibration state
  bool _isCalibrating = false;
  final List<double> _calibrationReadings = <double>[];
  double _ambientDb = 50.0;
  double _dynamicThreshold = 60.0;
  bool _calibrated = false;

  // Sustained detection state
  int _consecutiveAboveThreshold = 0;
  bool _blowActive = false;

  Stream<double> get blowStrengthStream => _blowStrengthController.stream;
  bool get isCalibrated => _calibrated;
  bool get isCalibrating => _isCalibrating;

  Future<bool> start() async {
    final PermissionStatus status = await Permission.microphone.request();
    if (!status.isGranted) {
      return false;
    }

    if (_subscription != null) {
      return true;
    }

    _noiseMeter = NoiseMeter();
    _subscription = _noiseMeter!.noise.listen(
      _handleReading,
      onError: _handleError,
      cancelOnError: false,
    );
    return true;
  }

  /// Begin calibration phase — collect ambient noise readings.
  void startCalibration() {
    _isCalibrating = true;
    _calibrated = false;
    _calibrationReadings.clear();
    _consecutiveAboveThreshold = 0;
    _blowActive = false;
  }

  /// End calibration phase — compute ambient baseline and dynamic threshold.
  void finishCalibration() {
    _isCalibrating = false;
    if (_calibrationReadings.isNotEmpty) {
      final List<double> sorted = List<double>.of(_calibrationReadings)..sort();
      _ambientDb = sorted[sorted.length ~/ 2];
    }
    _dynamicThreshold = _ambientDb + _ambientOffsetDb;
    _calibrated = true;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _noiseMeter = null;
    _isCalibrating = false;
    _consecutiveAboveThreshold = 0;
    _blowActive = false;
    if (!_isDisposed) {
      _blowStrengthController.add(0);
    }
  }

  void _handleReading(NoiseReading reading) {
    if (_isDisposed) {
      return;
    }

    final double db = reading.meanDecibel;

    if (_isCalibrating) {
      _calibrationReadings.add(db);
      _blowStrengthController.add(0);
      return;
    }

    if (db > _dynamicThreshold) {
      _consecutiveAboveThreshold++;
    } else {
      _consecutiveAboveThreshold = 0;
      _blowActive = false;
    }

    if (_consecutiveAboveThreshold >= _sustainedTicks) {
      _blowActive = true;
    }

    if (_blowActive) {
      final double normalized =
          ((db - _dynamicThreshold) / _breathRangeDb).clamp(0.0, 1.0);
      _blowStrengthController.add(normalized);
    } else {
      _blowStrengthController.add(0);
    }
  }

  void _handleError(Object error) {
    if (!_isDisposed) {
      _blowStrengthController.add(0);
    }
  }

  void dispose() {
    _isDisposed = true;
    _subscription?.cancel();
    _subscription = null;
    _noiseMeter = null;
    _blowStrengthController.close();
  }
}
