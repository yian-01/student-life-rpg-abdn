import 'package:flutter/material.dart';

const profileAvatars = {
  'cat': '小猫',
  'fox': '狐狸',
  'rabbit': '兔子',
  'leaf': '绿叶',
  'star': '星星',
};

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(this.avatar, {super.key, this.size = 56});
  final String avatar;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: profileAvatars[avatar] ?? '像素头像',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _Avatar(avatar)),
    ),
  );
}

class _Avatar extends CustomPainter {
  const _Avatar(this.avatar);
  final String avatar;
  @override
  void paint(Canvas canvas, Size size) {
    final rows = switch (avatar) {
      'rabbit' => [
        '..aa..aa..',
        '..aa..aa..',
        '..ab..ba..',
        '..aaaaaa..',
        '.aaaaaaaa.',
        '.acaaaaca.',
        '.aaaaaaaa.',
        '..aaddaaa.',
        '...aaaa...',
        '..........',
      ],
      'leaf' => [
        '..........',
        '......aaa.',
        '....aaaaa.',
        '..aaaaaaa.',
        '.aaaaabaa.',
        '.aaaabaa..',
        '.aaabaa...',
        '..abaa....',
        '..aa......',
        '..........',
      ],
      'star' => [
        '....aa....',
        '...aaaa...',
        '...aaaa...',
        'aaaaaaaaaa',
        '.acaaaaca.',
        '..aaaaaa..',
        '..aaaaaa..',
        '.aaa..aaa.',
        '.aa....aa.',
        '..........',
      ],
      _ => [
        '.aa....aa.',
        '.aba..aba.',
        '.aaaaaaaa.',
        'aaaaaaaaaa',
        'aacaaaacaa',
        'aaaaaaaaaa',
        '.aaaddaaa.',
        '..aaaaaa..',
        '...aaaa...',
        '..........',
      ],
    };
    final primary = switch (avatar) {
      'fox' => const Color(0xFFC78957),
      'rabbit' => const Color(0xFFC8A9B7),
      'leaf' => const Color(0xFF79A181),
      'star' => const Color(0xFFD8B76A),
      _ => const Color(0xFF9BA7B8),
    };
    final colors = {
      'a': primary,
      'b': const Color(0xFFE8C5C7),
      'c': const Color(0xFF37403C),
      'd': const Color(0xFFF3E2D5),
    };
    final cell = size.shortestSide / 10;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length && x < 10; x++) {
        final color = colors[rows[y][x]];
        if (color != null) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell, cell),
            paint..color = color,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Avatar old) => old.avatar != avatar;
}
