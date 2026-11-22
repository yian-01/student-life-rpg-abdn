import 'dart:ui' as ui;

/// Small raster sprites retain hard pixel edges when they turn or flip.
abstract final class PixelLeaves {
  static final _images = <String, ui.Image>{};
  static Future<void>? _loading;
  static const patterns = <String, List<String>>{
    'cherry': [
      '................',
      '.....11..11.....',
      '....12211221....',
      '...1222222221...',
      '...1222222221...',
      '....12222221....',
      '....12222221....',
      '.....122221.....',
      '......1221......',
      '.......21.......',
      '.......3........',
      '.......3........',
    ],
    'bush': [
      '................',
      '.........11.....',
      '.......1221.....',
      '.....122221.....',
      '....1222221.....',
      '...12223221.....',
      '...1223221......',
      '...123221.......',
      '....1321........',
      '....31..........',
      '...3............',
      '................',
    ],
    'maple': [
      '.......1........',
      '......121.......',
      '..1...121...1...',
      '..21.12221.12...',
      '...2212221221...',
      '.11222232222211.',
      '..122223222221..',
      '...1222322221...',
      '..122223222221..',
      '......131.......',
      '.......3........',
      '.......3........',
    ],
    'ginkgo': [
      '................',
      '..1111....1111..',
      '.122221..122221.',
      '.12222211222221.',
      '.12222233222221.',
      '..122223222221..',
      '...1222322221...',
      '....12232221....',
      '.....123221.....',
      '......131.......',
      '.......3........',
      '.......3........',
    ],
    'bamboo': [
      '............1...',
      '..........121...',
      '........12221...',
      '......122221....',
      '.....122321.....',
      '....122321......',
      '...122321.......',
      '..122321........',
      '..12321.........',
      '...31...........',
      '..3.............',
      '................',
    ],
  };
  static const _palettes = <String, List<int>>{
    'cherry': [0xFFF1C2D1, 0xFFD58CA8, 0xFFB9688B],
    'bush': [0xFFB4C67A, 0xFF8DA950, 0xFF58733C],
    'maple': [0xFFF3C27E, 0xFFDA9651, 0xFFAF663B],
    'ginkgo': [0xFFE8DD92, 0xFFD0BE62, 0xFF9D8A3C],
    'bamboo': [0xFFA8BD96, 0xFF789969, 0xFF4D7150],
  };

  static Future<void> load() => _loading ??= _load();
  static ui.Image image(String name) => _images[name]!;

  static Future<void> _load() async {
    for (final entry in patterns.entries) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final palette = _palettes[entry.key]!;
      for (var y = 0; y < entry.value.length; y++) {
        for (var x = 0; x < entry.value[y].length; x++) {
          final color = int.tryParse(entry.value[y][x]);
          if (color == null) continue;
          canvas.drawRect(
            ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
            ui.Paint()
              ..isAntiAlias = false
              ..color = ui.Color(palette[color - 1]),
          );
        }
      }
      final picture = recorder.endRecording();
      _images[entry.key] = await picture.toImage(16, 16);
      picture.dispose();
    }
  }
}
