import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/finance/models/money.dart';

void main() {
  test('parses yuan text into minor units', () {
    expect(parseAmountMinor('0.01'), 1);
    expect(parseAmountMinor('3.50'), 350);
    expect(parseAmountMinor('  3.5 '), 350);
    expect(parseAmountMinor('3'), 300);
    expect(parseAmountMinor('21474836.47'), 2147483647);
  });

  test('rejects illegal amount text', () {
    for (final input in [
      '',
      '   ',
      '-1',
      '-0.01',
      '1e2',
      '1E2',
      '3.141',
      '+3.50',
      '.50',
      '3.',
      '1.2.3',
      'abc',
      '3.50.1',
      '21474836.48',
      '21474837',
    ]) {
      expect(
        () => parseAmountMinor(input),
        throwsFormatException,
        reason: input,
      );
    }
  });

  test('zero is rejected by default and allowed for budget', () {
    expect(() => parseAmountMinor('0'), throwsFormatException);
    expect(() => parseAmountMinor('0.00'), throwsFormatException);
    expect(parseAmountMinor('0', allowZero: true), 0);
    expect(parseAmountMinor('0.00', allowZero: true), 0);
  });

  test('formats minor units with two decimals', () {
    expect(formatAmountMinor(-5000), '-50.00');
    expect(formatAmountMinor(1), '0.01');
    expect(formatAmountMinor(350), '3.50');
    expect(formatAmountMinor(0), '0.00');
  });

  test('addAmountMinor rejects overflow', () {
    expect(addAmountMinor(1, 2), 3);
    expect(() => addAmountMinor(maxAmountMinor, 1), throwsArgumentError);
  });
}
