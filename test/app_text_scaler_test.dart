import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/core/storage/reading_settings.dart';
import 'package:review_x/core/theme/app_text_scaler.dart';

void main() {
  test('app text size composes with platform nonlinear scaling', () {
    const scaler = AppTextScaler(_NonlinearTextScaler(), 1.25);
    expect(scaler.scale(20), 35.5);
    expect(scaler, const AppTextScaler(_NonlinearTextScaler(), 1.25));
  });

  test('app text size stays within its supported range', () {
    expect(validatedReading({'appTextScale': 0.1})['appTextScale'], 0.8);
    expect(validatedReading({'appTextScale': 2.0})['appTextScale'], 1.4);
  });
}

class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 20 ? fontSize * 1.5 : 30 + (fontSize - 20) * 1.1;

  @override
  double get textScaleFactor => 1.5;
}
