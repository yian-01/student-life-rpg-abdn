const int maxAmountMinor = 2147483647;

int parseAmountMinor(String input, {bool allowZero = false}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Amount must not be empty.');
  }
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(trimmed)) {
    throw const FormatException(
      'Amount must be digits with at most two decimals.',
    );
  }

  final parts = trimmed.split('.');
  final whole = int.parse(parts[0]);
  final fraction = parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;
  final maxWhole = maxAmountMinor ~/ 100;
  final maxFraction = maxAmountMinor % 100;

  if (whole > maxWhole || (whole == maxWhole && fraction > maxFraction)) {
    throw const FormatException('Amount exceeds 2147483647 minor units.');
  }

  final amountMinor = whole * 100 + fraction;
  if (amountMinor == 0 && !allowZero) {
    throw const FormatException('Amount must be greater than zero.');
  }
  return amountMinor;
}

String formatAmountMinor(int amountMinor) {
  final sign = amountMinor < 0 ? '-' : '';
  final absolute = amountMinor.abs();
  final major = absolute ~/ 100;
  final minor = absolute % 100;
  return '$sign$major.${minor.toString().padLeft(2, '0')}';
}

int addAmountMinor(int left, int right) {
  final sum = left + right;
  if (sum > maxAmountMinor) {
    throw ArgumentError('Aggregated amount exceeds 2147483647 minor units.');
  }
  return sum;
}
