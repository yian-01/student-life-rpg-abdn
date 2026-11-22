import 'dart:js_interop';

@JS('keyuGardenAudio')
external void _audio(JSBoolean enabled, JSNumber speed, JSBoolean rustle);

abstract final class GardenAudio {
  static bool _enabled = false;
  static Future<bool> enable(bool enabled) async {
    try {
      _audio(enabled.toJS, 0.toJS, false.toJS);
      _enabled = enabled;
      return true;
    } catch (_) {
      _enabled = false;
      return false;
    }
  }

  static void wind(double speed) {
    if (_enabled) _audio(true.toJS, speed.toJS, false.toJS);
  }

  static void rustle() {
    if (_enabled) _audio(true.toJS, 0.toJS, true.toJS);
  }
}
