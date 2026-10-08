import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/core/services/google_translate_service.dart';
import 'package:review_x/twitter/api/transaction_id.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/session.dart';
import 'package:review_x/twitter/models/social_models.dart';

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
    });

    test('parses Grok translation with empty destination language', () {
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
    });

    test('handles is_available: false', () {
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
    });

    test('handles missing Grok field', () {
      final data = sampleTweet(); // No grok field
      final post = SocialPost.parse(data);
      expect(post, isNotNull);
      expect(post?.translatedText, isEmpty);
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
            'translation': '外层包装解包成功',
            'entities': {'urls': []}
          }
        }
      };

      final post = SocialPost.parse(wrapped);
      expect(post, isNotNull);
      expect(post?.translatedText, '外层包装解包成功');
    });
  });

  group('GoogleTranslateService', () {
    test('needsTranslation identifies non-Chinese text', () {
      expect(GoogleTranslateService.needsTranslation('Hello world'), isTrue);
      expect(GoogleTranslateService.needsTranslation('你好，世界'), isFalse);
    });
  });

  group('TwitterClient request headers', () {
    test('sends Accept-Language header prioritizing Chinese', () async {
      final transport = TestTransport({
        'data': {'user': {}}
      });
      final dio = Dio()..httpClientAdapter = transport;
      final client = TwitterClient(dio: dio, transactions: TestTransactions());
      client.session = const TwitterSession(
        'auth_token=test-auth; ct0=test-ct0',
        '12345',
      );

      await client.accountSettings();

      expect(transport.requests.length, 1);
      final headers = transport.requests.first.headers;
      expect(headers['Accept-Language'], contains('zh-CN,zh;q=0.9'));
      expect(headers['x-twitter-client-language'], 'zh-cn');
    });
  });
}
