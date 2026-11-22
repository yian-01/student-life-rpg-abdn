import 'package:flutter/services.dart';

abstract final class GardenAudio {
  static bool _enabled = false;
  static Future<bool> enable(bool enabled) async {
    _enabled = enabled;
    return true;
  }

  static void wind(double speed) {}
  static void rustle() {
    if (_enabled) SystemSound.play(SystemSoundType.click);
  }
}
