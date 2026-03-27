import 'dart:async';

import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

class MicService {
  static const double _baselineDb = 50;
  static const double _maxDb = 90;

  final StreamController<double> _blowStrengthController =
      StreamController<double>.broadcast();

  NoiseMeter? _noiseMeter;
  StreamSubscription<NoiseReading>? _subscription;
  bool _isDisposed = false;

  Stream<double> get blowStrengthStream => _blowStrengthController.stream;

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

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _noiseMeter = null;
    if (!_isDisposed) {
      _blowStrengthController.add(0);
    }
  }

  void _handleReading(NoiseReading reading) {
    if (_isDisposed) {
      return;
    }
    final double normalized =
        ((reading.meanDecibel - _baselineDb) / (_maxDb - _baselineDb)).clamp(
          0.0,
          1.0,
        );
    _blowStrengthController.add(normalized);
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
