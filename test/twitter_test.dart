import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/twitter/api/transaction_id.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/session.dart';
import 'package:review_x/twitter/models/social_models.dart';
import 'package:review_x/twitter/repositories/twitter_adapter.dart';

Map<String, dynamic> user() => {
      '__typename': 'User',
      'rest_id': '1',
      'core': {'name': 'Test', 'screen_name': 'test'},
      'avatar': {
        'image_url': 'https://pbs.twimg.com/profile_images/test_normal.jpg'
      },
      'legacy': {'followers_count': 8, 'friends_count': 3}
    };
Map<String, dynamic> tweet(String id, {String text = 'hello'}) => {
      '__typename': 'Tweet',
      'rest_id': id,
      'core': {
        'user_results': {'result': user()}
      },
      'legacy': {
        'full_text': text,
        'favorite_count': 4,
        'retweet_count': 2,
        'reply_count': 1,
        'favorited': true,
        'created_at': 'Wed Oct 01 08:00:00 +0000 2025'
      }
    };
Map<String, dynamic> item(dynamic post) => {
      'tweet_results': {'result': post}
    };
Map<String, dynamic> entry(dynamic post) => {
      'content': {'itemContent': item(post)}
    };
Map<String, dynamic> timeline() => {
      'instructions': [
        {
          'type': 'TimelineAddEntries',
          'entries': [
            entry(tweet('2')),
            {
              'content': {
                'items': [
                  {
                    'item': {'itemContent': item(tweet('3'))}
                  }
                ]
              }
            },
            entry(tweet('2')),
            {
              'content': {'cursorType': 'Bottom', 'value': 'opaque:next'}
            }
          ]
        }
      ]
    };

class FixedTransactions extends TransactionIds {
  @override
  Future<String> create(String method, String path) async =>
      'public-test-transaction';
}

class StubTransport implements HttpClientAdapter {
  StubTransport(this.response, {this.status = 200, this.timeout = false});
  final dynamic response;
  final int status;
  final bool timeout;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    requests.add(options);
    if (timeout) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.receiveTimeout);
    }
    return ResponseBody.fromString(jsonEncode(response), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

TwitterClient client(StubTransport transport) {
  final dio =
      Dio(BaseOptions(validateStatus: (_) => true, followRedirects: false))
        ..httpClientAdapter = transport;
  return TwitterClient(dio: dio, transactions: FixedTransactions())
    ..session = const TwitterSession(
        'auth_token=test-only; ct0=csrf-test-only; twid=u%3D1', '1');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('explore default and objective trends use distinct guide parameters',
      () async {
    final transport = StubTransport({
      'timeline': {'instructions': []}
    });
    final api = client(transport);
    await api.trendsGuide(personalized: true);
    await api.trendsGuide();
    expect(transport.requests.first.queryParameters.containsKey('tab_category'),
        isFalse);
    expect(transport.requests.last.queryParameters['tab_category'],
        'objective_trends');
  });
  test(
      'recommendations accept list responses and exclude self and followed users',
      () async {
    final transport = StubTransport([
      for (final id in ['1', '2', '3', '2'])
        {
          'user_id': id,
          'user': {
            'id_str': id,
            'screen_name': 'user$id',
            'name': 'User $id',
            'following': id == '3'
          },
        }
    ]);
    final users = await TwitterAdapter(client(transport)).recommendedUsers();
    expect(users.map((u) => u.id), ['2']);
    expect(transport.requests.single.path,
        endsWith('/1.1/users/recommendations.json'));
  });
  test('guide preserves server region descriptions', () {
    final trends = TrendingTopic.parseGuide({
      'timeline': {
        'instructions': [
          {
            'addEntries': {
              'entries': [
                {
                  'content': {
                    'item': {
                      'content': {
                        'trend': {
                          'name': 'Penn State',
                          'description': '美国 的趋势',
                          'metaDescription': 'Northwestern'
                        }
                      }
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    });
    expect(trends.single.description, '美国 的趋势');
    expect(trends.single.metaDescription, 'Northwestern');
  });
  test('Cookie normalization keeps only X fields and preserves equals', () {
    expect(
        TwitterSession.normalize(
            ' other=value; ct0=abc=def; auth_token=test; twid=u%3D1 '),
        'auth_token=test; ct0=abc=def; twid=u%3D1');
    expect(TwitterSession.userIdFromCookie('twid="u%3D123"'), '123');
    expect(() => TwitterSession.normalize('auth_token=test'),
        throwsFormatException);
    expect(
        () =>
            TwitterSession.normalize('auth_token=test; ct0=a\r\nInjected: yes'),
        throwsFormatException);
  });
  test('current split user fields and legacy fields both parse', () {
    expect(SocialUser.parse(user())!.avatar, contains('_bigger.jpg'));
    expect(
        SocialUser.parse({
          'rest_id': '1',
          'legacy': {'name': 'Old', 'screen_name': 'old'}
        })!
            .handle,
        'old');
    expect(SocialUser.parse({'__typename': 'UserUnavailable'}), isNull);
  });
  test('long text and quote parse before publication, visibility unwraps', () {
    final raw = tweet('2')
      ..['note_tweet'] = {
        'note_tweet_results': {
          'result': {'text': '完整长帖'}
        }
      }
      ..['quoted_status_result'] = {'result': tweet('4')};
    final post = SocialPost.parse(
        {'__typename': 'TweetWithVisibilityResults', 'tweet': raw})!;
    expect(post.text, '完整长帖');
    expect(post.quote!.id, '4');
    expect(post.createdAt!.hour, 8);
  });
  test('repost resolves original author and keeps reposter attribution', () {
    final raw = tweet('9');
    (raw['legacy'] as Map)['retweeted_status_result'] = {'result': tweet('2')};
    final post = SocialPost.parse(raw)!;
    expect(post.id, '2');
    expect(post.repostedBy, 'Test');
  });
  test('timeline modules deduplicate rows, exclude promotions and keep cursor',
      () {
    final tl = timeline();
    final entries = (tl['instructions'][0]['entries'] as List);
    entries.add({
      'content': {
        'itemContent': {...item(tweet('5')), 'promotedMetadata': {}}
      }
    });
    final quoted = tweet('6')
      ..['quoted_status_result'] = {'result': tweet('7')};
    entries.add(entry(quoted));
    final page = PostPage.parse(tl);
    expect(page.posts.map((p) => p.id), ['2', '3', '6']);
    expect(page.cursor, 'opaque:next');
  });
  test('module append and replaced bottom cursor are supported', () {
    final page = PostPage.parse({
      'instructions': [
        {
          'moduleItems': [
            {
              'item': {'itemContent': item(tweet('3'))}
            }
          ]
        },
        {
          'entry': {
            'content': {'cursorType': 'Bottom', 'value': 'next'}
          }
        }
      ]
    });
    expect(page.posts.single.id, '3');
    expect(page.cursor, 'next');
  });
  test('video chooses largest MP4 and rejects unrelated media hosts', () {
    final media = SocialMedia.parse({
      'media_url_https': 'https://pbs.twimg.com/media/test.jpg',
      'video_info': {
        'variants': [
          {
            'content_type': 'video/mp4',
            'bitrate': 100,
            'url': 'https://video.twimg.com/low.mp4'
          },
          {
            'content_type': 'video/mp4',
            'bitrate': 200,
            'url': 'https://video.twimg.com/high.mp4'
          }
        ]
      }
    })!;
    expect(media.video, endsWith('high.mp4'));
    expect(safeMediaUrl('https://video.twimg.com.evil.test/a'), isFalse);
  });
  test('transaction XOR envelope contains key, little endian time and digest',
      () {
    final encoded = TransactionIds.encode(
        method: 'GET',
        path: '/graphql/id/op',
        verification: base64Encode([1, 2, 3]),
        animationKey: 'test',
        time: 0x01020304,
        mask: 7);
    final bytes = base64Decode(base64.normalize(encoded));
    expect(encoded, 'BwYFBAMEBQa4LRsurVpWFVPhMuqT/t3ZBA');
    expect(bytes.first, 7);
    expect(bytes.skip(1).take(7).map((b) => b ^ 7), [1, 2, 3, 4, 3, 2, 1]);
    expect(bytes.last ^ 7, 3);
    expect(bytes.length, 25);
  });
  test('transaction IDs load their pairs from the bundled asset', () async {
    final transactions = TransactionIds(
      random: Random(7),
      clock: () => DateTime.utc(2026, 10, 3),
    );
    final encoded = await transactions.create('GET', '/graphql/id/op');
    final bytes = base64Decode(base64.normalize(encoded));
    expect(bytes.length, 70);
  });
  test(
      'following endpoint sends exact cursor, CSRF and session only to api.x.com',
      () async {
    final transport = StubTransport({
      'data': {
        'home': {'home_timeline_urt': timeline()}
      }
    });
    final page =
        await TwitterAdapter(client(transport)).home(cursor: 'opaque input');
    expect(page.posts.length, 2);
    final request = transport.requests.single;
    expect(request.uri.host, 'api.x.com');
    expect(request.path, endsWith('/HomeLatestTimeline'));
    expect(request.headers['x-csrf-token'], 'csrf-test-only');
    expect(request.followRedirects, isFalse);
    expect(jsonDecode(request.queryParameters['variables'])['cursor'],
        'opaque input');
  });
  test('user timeline unwraps the extra timeline object', () async {
    final transport = StubTransport({
      'data': {
        'user': {
          'result': {
            'timeline_v2': {'timeline': timeline()}
          }
        }
      }
    });
    expect(
        (await TwitterAdapter(client(transport)).userPosts('1')).posts.length,
        2);
  });
  test('unknown timeline structure fails visibly rather than returning empty',
      () async {
    final transport = StubTransport({
      'data': {'home': {}}
    });
    expect(TwitterAdapter(client(transport)).home(),
        throwsA(isA<TwitterFailure>()));
  });
  test('HTTP 200 business auth error requests reauthentication', () async {
    final transport = StubTransport({
      'errors': [
        {'code': 89, 'message': 'Invalid token'}
      ]
    });
    expect(
        client(transport).call('HomeLatestTimeline', {}),
        throwsA(isA<TwitterFailure>()
            .having((e) => e.sessionExpired, 'expired', true)));
  });
  test('rate limiting is distinct from session expiry', () async {
    final transport = StubTransport({}, status: 429);
    expect(
        client(transport).call('HomeLatestTimeline', {}),
        throwsA(isA<TwitterFailure>()
            .having((e) => e.sessionExpired, 'expired', false)));
  });
  test('mutation timeout has uncertain result and is never retried', () async {
    final transport = StubTransport({}, timeout: true);
    await expectLater(
        TwitterAdapter(client(transport)).like('2', true),
        throwsA(isA<TwitterFailure>()
            .having((e) => e.uncertain, 'uncertain', true)));
    expect(transport.requests.length, 1);
  });
  test(
      'read timeout explains VPN check without expiring the session or retrying',
      () async {
    final transport = StubTransport({}, timeout: true);
    await expectLater(
        client(transport).call('HomeLatestTimeline', {}),
        throwsA(isA<TwitterFailure>()
            .having((e) => e.message, 'message', contains('VPN 或代理'))
            .having((e) => e.sessionExpired, 'expired', false)
            .having((e) => e.uncertain, 'uncertain', false)));
    expect(transport.requests.length, 1);
  });
  test('like requires explicit Done confirmation', () async {
    final transport = StubTransport({'data': {}});
    expect(TwitterAdapter(client(transport)).like('2', true),
        throwsA(isA<TwitterFailure>()));
  });
  test('unlike chooses UnfavoriteTweet based on current action', () async {
    final transport = StubTransport({
      'data': {'unfavorite_tweet': 'Done'}
    });
    await TwitterAdapter(client(transport)).like('2', false);
    expect(transport.requests.single.path, endsWith('/UnfavoriteTweet'));
  });
  test('undo repost uses source_tweet_id and retweet_results response',
      () async {
    final transport = StubTransport({
      'data': {
        'create_retweet': {
          'retweet_results': {
            'result': {'rest_id': '2'}
          }
        }
      }
    });
    await TwitterAdapter(client(transport)).repost('2', false);
    expect(transport.requests.single.path, endsWith('/DeleteRetweet'));
    expect(transport.requests.single.data['variables']['source_tweet_id'], '2');
  });
  test('local action count cannot become negative', () {
    final post = SocialPost(
        id: '1', author: SocialUser.parse(user())!, text: '', liked: true);
    expect(post.withActions(liked: false).likes, 0);
  });
}
