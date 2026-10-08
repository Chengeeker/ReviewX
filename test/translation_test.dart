import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/twitter/api/transaction_id.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/session.dart';
import 'package:review_x/twitter/models/social_models.dart';
import 'package:review_x/twitter/models/translation_diagnostics.dart';

class TestTransactions extends TransactionIds {
  @override
  Future<String> create(String method, String path) async => 'trans-test-id';
}

class TestTransport implements HttpClientAdapter {
  TestTransport(this.response);
  final dynamic response;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<dynamic>? stream,
      Future<void>? cancel) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(response), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    TranslationDiagnostics.clear();
  });

  group('TranslationDiagnostics', () {
    test('records and retrieves log entries correctly', () {
      final entry = TranslationLogEntry(
        postId: '1001',
        authorHandle: 'testuser',
        textPreview: 'Hello world',
        hasGrokField: true,
        isAvailable: true,
        destinationLanguage: 'zh-cn',
        translationPreview: '你好世界',
        resultStatus: '成功解析译文',
        detailReason: '目标语言为 zh-cn，成功提取',
        timestamp: DateTime(2026, 10, 8, 12, 0),
      );

      TranslationDiagnostics.record(entry);
      expect(TranslationDiagnostics.logs.length, 1);
      final retrieved = TranslationDiagnostics.getForPost('1001');
      expect(retrieved, isNotNull);
      expect(retrieved?.authorHandle, 'testuser');
      expect(retrieved?.resultStatus, '成功解析译文');
      expect(retrieved?.toFormattedReport(), contains('你好世界'));
    });

    test('exports formatted report for all logs', () {
      TranslationDiagnostics.record(TranslationLogEntry(
        postId: '1002',
        authorHandle: 'alice',
        textPreview: 'Test 1',
        hasGrokField: false,
        isAvailable: null,
        destinationLanguage: '',
        translationPreview: '',
        resultStatus: 'X未下发Grok数据',
        detailReason: '接口未返回字段',
        timestamp: DateTime(2026, 10, 8, 12, 1),
      ));

      final report = TranslationDiagnostics.exportAll();
      expect(report, contains('=== ReviewX 翻译诊断与日志导出报告 ==='));
      expect(report, contains('[推文 ID]: 1002'));
      expect(report, contains('X未下发Grok数据'));
    });
  });

  group('SocialPost translation parsing', () {
    Map<String, dynamic> sampleUser() => {
          '__typename': 'User',
          'rest_id': '99',
          'core': {'name': 'Author', 'screen_name': 'author'},
          'avatar': {'image_url': 'https://x.com/avatar.jpg'},
          'legacy': {'followers_count': 10, 'friends_count': 5}
        };

    Map<String, dynamic> sampleTweet({
      Map<String, dynamic>? grokField,
      String? typename = 'Tweet',
    }) =>
        {
          '__typename': typename,
          'rest_id': '2001',
          'core': {
            'user_results': {'result': sampleUser()}
          },
          'legacy': {
            'full_text': 'Good morning everyone!',
            'favorite_count': 1,
            'retweet_count': 0,
            'reply_count': 0,
            'created_at': 'Thu Oct 08 08:00:00 +0000 2026'
          },
          if (grokField != null)
            'grok_translated_post_with_availability': grokField,
        };

    test('parses standard zh-cn Grok translation', () {
      final data = sampleTweet(grokField: {
        'is_available': true,
        'data': {
          'destination_language': 'zh-CN',
          'translation': '大家早上好！',
          'entities': {'urls': []}
        }
      });

      final post = SocialPost.parse(data);
      expect(post, isNotNull);
      expect(post?.translatedText, '大家早上好！');
      final diag = TranslationDiagnostics.getForPost('2001');
      expect(diag?.resultStatus, '成功解析译文');
    });

    test('parses Grok translation with empty destination language but Chinese chars', () {
      final data = sampleTweet(grokField: {
        'is_available': true,
        'data': {
          'destination_language': '',
          'translation': '大家好！这是自动翻译的内容。',
          'entities': {'urls': []}
        }
      });

      final post = SocialPost.parse(data);
      expect(post, isNotNull);
      expect(post?.translatedText, '大家好！这是自动翻译的内容。');
      final diag = TranslationDiagnostics.getForPost('2001');
      expect(diag?.resultStatus, '成功解析译文');
    });

    test('handles is_available: false with proper diagnostic logging', () {
      final data = sampleTweet(grokField: {
        'is_available': false,
        'data': {
          'destination_language': 'zh-cn',
          'translation': '',
        }
      });

      final post = SocialPost.parse(data);
      expect(post, isNotNull);
      expect(post?.translatedText, isEmpty);
      final diag = TranslationDiagnostics.getForPost('2001');
      expect(diag?.resultStatus, contains('is_available=false'));
    });

    test('handles missing Grok field with proper diagnostic logging', () {
      final data = sampleTweet(); // No grok field
      final post = SocialPost.parse(data);
      expect(post, isNotNull);
      expect(post?.translatedText, isEmpty);
      final diag = TranslationDiagnostics.getForPost('2001');
      expect(diag?.resultStatus, 'X未下发Grok数据');
    });

    test('handles outer grok_translated_post_with_availability in TweetWithVisibilityResults', () {
      final tweetData = sampleTweet();
      final wrapped = {
        '__typename': 'TweetWithVisibilityResults',
        'tweet': tweetData,
        'grok_translated_post_with_availability': {
          'is_available': true,
          'data': {
            'destination_language': 'zh',
            'translation': '外层包裹的翻译测试',
            'entities': {'urls': []}
          }
        }
      };

      final post = SocialPost.parse(wrapped);
      expect(post, isNotNull);
      expect(post?.translatedText, '外层包裹的翻译测试');
    });
  });

  group('TwitterClient request headers', () {
    test('sends Accept-Language header prioritizing Chinese', () async {
      final transport = TestTransport({
        'data': {'home': {}}
      });
      final dio = Dio()..httpClientAdapter = transport;
      final client = TwitterClient(dio: dio, transactions: TestTransactions())
        ..session = const TwitterSession('auth_token=a; ct0=b', '123');

      try {
        await client.trendsGuide();
      } catch (_) {}

      expect(transport.requests.isNotEmpty, isTrue);
      final headers = transport.requests.first.headers;
      expect(headers['Accept-Language'], contains('zh-CN'));
      expect(headers['x-twitter-client-language'], 'zh-cn');
    });
  });
}
