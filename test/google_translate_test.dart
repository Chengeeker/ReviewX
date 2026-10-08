import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/core/services/google_translate_service.dart';

void main() {
  test('GoogleTranslateService.needsTranslation detects foreign text', () {
    expect(GoogleTranslateService.needsTranslation('Hello world, this is a test.'), isTrue);
    expect(GoogleTranslateService.needsTranslation('你好，这是中文测试。'), isFalse);
    expect(GoogleTranslateService.needsTranslation('Hello 这是中英混排。'), isFalse);
    expect(GoogleTranslateService.needsTranslation('123'), isFalse);
    expect(GoogleTranslateService.needsTranslation('Day 3 (encore)/\n\nWe silently re-shipped codex cloud.'), isTrue);
  });

  test('GoogleTranslateService.translate translates English to Chinese', () async {
    final result = await GoogleTranslateService.translate('Hello world');
    expect(result, isNotNull);
    expect(result!.contains('你好') || result.contains('世界'), isTrue);
  });
}
