import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/models/social_models.dart';
import 'package:review_x/twitter/models/content_models.dart';
import 'package:review_x/twitter/repositories/twitter_adapter.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/core/storage/reading_settings.dart';
import 'package:review_x/core/services/settings_backup.dart';
import 'package:review_x/core/services/notification_poll.dart';
import 'twitter_test.dart' as fixtures;

Map<String, dynamic> articleFixture() => {
      'rest_id': 'article1',
      'title': '文章标题',
      'preview_text': '文章摘要',
      'cover_media': {
        'media_info': {
          'original_img_url': 'https://pbs.twimg.com/a.jpg',
          'original_img_width': 100,
          'original_img_height': 60
        }
      },
      'media_entities': [
        {
          'media_id': 'm1',
          'media_info': {'original_img_url': 'https://pbs.twimg.com/b.jpg'}
        }
      ],
      'content_state': {
        'entityMap': [
          {
            'key': '0',
            'value': {
              'type': 'LINK',
              'data': {'url': 'https://example.com'}
            }
          },
          {
            'key': '1',
            'value': {
              'type': 'MEDIA',
              'data': {
                'caption': '图片说明',
                'mediaItems': [
                  {'mediaId': 'm1'}
                ]
              }
            }
          },
        ],
        'blocks': [
          {'type': 'header-one', 'text': '标题'},
          {
            'type': 'unstyled',
            'text': 'bold link',
            'inlineStyleRanges': [
              {'offset': 0, 'length': 4, 'style': 'BOLD'}
            ],
            'entityRanges': [
              {'key': 0, 'offset': 5, 'length': 4}
            ]
          },
          {
            'type': 'atomic',
            'text': '',
            'entityRanges': [
              {'key': 1, 'offset': 0, 'length': 1}
            ]
          },
        ]
      },
    };
Map<String, dynamic> notificationTimeline() => {
      'instructions': [
        {
          'entries': [
            {
              'content': {'cursorType': 'Top', 'value': 'top'}
            },
            {
              'content': {
                'itemContent': {
                  'itemType': 'TimelineNotification',
                  'id': 'n1',
                  'timestamp_ms': '1760000000000',
                  'notification_icon': 'heart_icon',
                  'notification_url': {'url': 'https://x.com/i/status/2'},
                  'rich_message': {'text': 'Test 赞了你的帖子'},
                  'template': {
                    'from_users': [
                      {
                        'user_results': {'result': fixtures.user()}
                      }
                    ],
                    'target_objects': [
                      {
                        'tweet_results': {'result': fixtures.tweet('2')}
                      }
                    ]
                  }
                }
              }
            },
            {
              'content': {'cursorType': 'Bottom', 'value': 'next'}
            }
          ]
        }
      ]
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('new relationship false overrides stale legacy true', () {
    final user = fixtures.user()
      ..['relationship_perspectives'] = {
        'following': false,
        'followed_by': false
      }
      ..['privacy'] = {'protected': false};
    user['legacy'] = <String, dynamic>{
      ...object(user['legacy']),
      'following': true,
      'followed_by': true,
      'protected': true
    };
    final parsed = SocialUser.parse(user)!;
    expect(parsed.isFollowing, false);
    expect(parsed.followedBy, false);
    expect(parsed.protected, false);
  });
  test('login validation checks account-owned settings against session user',
      () async {
    final transport = fixtures.StubTransport({
      'screen_name': 'test',
      'data': {
        'user': {'result': fixtures.user()}
      }
    });
    expect(
        (await TwitterAdapter(fixtures.client(transport)).validateSession()).id,
        '1');
    expect(transport.requests.first.method, 'GET');
    expect(
        transport.requests.first.path, endsWith('/1.1/account/settings.json'));
    expect(transport.requests.first.queryParameters['include_mention_filter'],
        true);
    final mismatch = fixtures.StubTransport({
      'screen_name': 'other',
      'data': {
        'user': {'result': fixtures.user()}
      }
    });
    await expectLater(
        TwitterAdapter(fixtures.client(mismatch)).validateSession(),
        throwsA(isA<TwitterFailure>()));
  });
  test('user list handles modules and never promotes embedded quoted posts',
      () {
    final page = UserPage.parse({
      'instructions': [
        {
          'entries': [
            {
              'content': {
                'items': [
                  {
                    'item': {
                      'itemContent': {
                        'itemType': 'TimelineUser',
                        'user_results': {'result': fixtures.user()}
                      }
                    }
                  }
                ]
              }
            },
            {
              'content': {
                'itemContent': {
                  'itemType': 'TimelineUser',
                  'promotedMetadata': {},
                  'user_results': {
                    'result': fixtures.user()..['rest_id'] = 'ad'
                  }
                }
              }
            },
            {
              'content': {'cursorType': 'Bottom', 'value': 'users-next'}
            }
          ]
        }
      ]
    });
    expect(page.users.map((u) => u.id), ['1']);
    expect(page.cursor, 'users-next');
  });
  test('protected follow request requires actual server request flag',
      () async {
    final user = fixtures.user();
    user['legacy'] = <String, dynamic>{
      ...object(user['legacy']),
      'protected': true,
      'follow_request_sent': true
    };
    final transport = fixtures.StubTransport({
      'data': {
        'user': {'result': user}
      }
    });
    final updated =
        await TwitterAdapter(fixtures.client(transport)).follow('1', true);
    expect(updated.followRequested, true);
    expect(transport.requests.length, 2);
    (user['legacy'] as Map)['follow_request_sent'] = false;
    final bad = fixtures.StubTransport({
      'data': {
        'user': {'result': user}
      }
    });
    await expectLater(
        TwitterAdapter(fixtures.client(bad)).follow('1', true),
        throwsA(isA<TwitterFailure>()
            .having((e) => e.uncertain, 'uncertain', true)));
  });
  test('article preserves blocks, styles, links and resolved media', () {
    final article = SocialArticle.parse(articleFixture())!;
    expect(article.full, isTrue);
    expect(article.cover!.width, 100);
    expect(article.blocks[1].styles.single['style'], 'BOLD');
    expect(article.blocks[1].links.single['url'], 'https://example.com');
    expect(
        article.blocks[2].media.single.preview, 'https://pbs.twimg.com/b.jpg');
    expect(article.blocks[2].caption, '图片说明');
    final excerpt =
        SocialArticle.parse({'title': '摘要', 'preview_text': '没有完整正文'})!;
    expect(excerpt.full, isFalse);
  });
  test('article rejects unsafe embeds and links', () {
    final value = articleFixture();
    (value['cover_media']['media_info'] as Map)['original_img_url'] =
        'https://untrusted.test/a.jpg';
    expect(SocialArticle.parse(value)!.cover, isNull);
    expect(safeLink('javascript:alert(1)'), isFalse);
    expect(safeLink('https://user:password@example.com'), isFalse);
  });
  test('poll and link bindings support legacy list representation', () {
    final card = {
      'legacy': {
        'binding_values': [
          for (final e in {
            'choice1_label': 'A',
            'choice2_label': 'B',
            'choice1_count': '3',
            'choice2_count': '1',
            'selected_choice': '2',
            'title': 'Link',
            'description': 'Description',
            'card_url': 'https://example.com/page'
          }.entries)
            {
              'key': e.key,
              'value': {'string_value': e.value}
            },
        ]
      }
    };
    expect(SocialPoll.parse(card)!.total, 4);
    expect(SocialPoll.parse(card)!.selected, 2);
    expect(LinkCard.parse(card)!.url, 'https://example.com/page');
  });
  test('notifications resolve actors, targets, real cursors and categories',
      () {
    final page = NotificationPageData.parse(notificationTimeline());
    expect(page.cursor, 'next');
    expect(page.topCursor, 'top');
    expect(page.notifications.single.actors.single.id, '1');
    expect(page.notifications.single.posts.single.id, '2');
    expect(NotificationPoll.category(page.notifications.single), 'likes');
  });
  test('search uses official product and encoded referer', () async {
    final transport = fixtures.StubTransport({
      'data': {
        'search_by_raw_query': {
          'search_timeline': {'timeline': fixtures.timeline()}
        }
      }
    });
    final page = await TwitterAdapter(fixtures.client(transport))
        .search('#中文', product: 'Latest', cursor: 'opaque');
    expect(page.posts.length, 2);
    final request = transport.requests.single;
    final variables = jsonDecode(request.queryParameters['variables']);
    expect(variables['product'], 'Latest');
    expect(variables['cursor'], 'opaque');
    expect(
        request.headers['Referer'], contains(Uri.encodeQueryComponent('#中文')));
  });
  test('notifications follow viewer_v2 and submit real form cursor', () async {
    final transport = fixtures.StubTransport({
      'data': {
        'viewer_v2': {
          'user_results': {
            'result': {
              'notification_timeline': {'timeline': notificationTimeline()}
            }
          }
        }
      }
    });
    expect(
        (await TwitterAdapter(fixtures.client(transport)).notifications())
            .topCursor,
        'top');
    final write = fixtures.StubTransport({});
    await TwitterAdapter(fixtures.client(write)).markNotificationsRead('top');
    expect(write.requests.single.path,
        'https://api.x.com/2/notifications/all/last_seen_cursor.json');
    expect(write.requests.single.data, {'cursor': 'top'});
    expect(
        write.requests.single.contentType, 'application/x-www-form-urlencoded');
  });
  test('REST writes retain uncertain/no retry policy and endpoint allowlist',
      () async {
    final transport = fixtures.StubTransport({}, timeout: true),
        api = fixtures.client(transport);
    await expectLater(
        api.rest('/1.1/friendships/create.json', {'user_id': '1'}),
        throwsA(isA<TwitterFailure>()
            .having((e) => e.uncertain, 'uncertain', true)));
    expect(transport.requests.length, 1);
    expect(() => api.rest('https://attacker.test', {}),
        throwsA(isA<TwitterFailure>()));
  });
  test('media/replies each use their own official operation', () async {
    for (final operation in ['UserMedia', 'UserTweetsAndReplies']) {
      final transport = fixtures.StubTransport({
        'data': {
          'user': {
            'result': {
              'timeline_v2': {'timeline': fixtures.timeline()}
            }
          }
        }
      });
      await TwitterAdapter(fixtures.client(transport))
          .userTimeline('1', operation: operation, cursor: 'more');
      expect(transport.requests.single.path, endsWith('/$operation'));
      expect(
          jsonDecode(
              transport.requests.single.queryParameters['variables'])['cursor'],
          'more');
    }
  });
  test('article explicitly asks for rich content state', () async {
    final post = fixtures.tweet('2')
      ..['article'] = {
        'article_results': {'result': articleFixture()}
      };
    final transport = fixtures.StubTransport({
      'data': {
        'tweetResult': {'result': post}
      }
    });
    expect(
        (await TwitterAdapter(fixtures.client(transport)).article('2'))
            .article!
            .full,
        isTrue);
    expect(
        jsonDecode(transport.requests.single.queryParameters['fieldToggles'])[
            'withArticleRichContentState'],
        true);
  });
  test('bookmarks require Done and preserve content in state updates',
      () async {
    final transport = fixtures.StubTransport({
      'data': {'tweet_bookmark_put': 'Done'}
    });
    await TwitterAdapter(fixtures.client(transport)).bookmark('2', true);
    expect(transport.requests.single.path, endsWith('/CreateBookmark'));
    final raw = fixtures.tweet('2')
      ..['article'] = {
        'article_results': {'result': articleFixture()}
      };
    final post =
        SocialPost.parse(raw)!.withActions(bookmarked: true, liked: false);
    expect(post.bookmarked, true);
    expect(post.article!.title, '文章标题');
    final bad = fixtures.StubTransport({'data': {}});
    await expectLater(
        TwitterAdapter(fixtures.client(bad)).bookmark('2', true),
        throwsA(isA<TwitterFailure>()
            .having((e) => e.uncertain, 'uncertain', true)));
  });
  test('publish sends reply/quote payload and requires confirmed ID', () async {
    final transport = fixtures.StubTransport({
      'data': {
        'create_tweet': {
          'tweet_results': {
            'result': {'rest_id': '123'}
          }
        }
      }
    });
    expect(
        await TwitterAdapter(fixtures.client(transport)).publish('真实文字',
            replyId: '2', quoteUrl: 'https://x.com/test/status/3'),
        '123');
    final variables = transport.requests.single.data['variables'];
    expect(variables['reply']['in_reply_to_tweet_id'], '2');
    expect(variables['attachment_url'], 'https://x.com/test/status/3');
    expect(transport.requests.single.data['features'].length, greaterThan(20));
    final bad = fixtures.StubTransport({'data': {}});
    await expectLater(
        TwitterAdapter(fixtures.client(bad)).publish('正文'),
        throwsA(isA<TwitterFailure>()
            .having((e) => e.uncertain, 'uncertain', true)));
  });
  test('backup whitelists settings and excludes sessions and history',
      () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 2,
      'haptics': true,
      'cookie': 'DO-NOT-EXPORT',
      'twitter_session_v1': 'DO-NOT-EXPORT',
      'webdav_config': 'DO-NOT-EXPORT',
      'history_1': 'DO-NOT-EXPORT'
    });
    final storage = await StorageService.init(),
        backup = SettingsBackup(await StorageService.init());
    expect(jsonEncode(backup.export()), isNot(contains('DO-NOT-EXPORT')));
    await backup.restore({
      'app': 'com.review.x',
      'schema': 1,
      'appearance': {'theme_mode': 99, 'haptics': false, 'cookie': 'bad'},
      'reading': {
        'fontSize': 999,
        'lineHeight': -5,
        'storageFolder': '../../secret'
      }
    });
    await storage.preferences.reload();
    expect(storage.getInt('theme_mode'), 2);
    expect(storage.getBool('haptics'), false);
    expect(storage.preferences.getString('cookie'), 'DO-NOT-EXPORT');
    final reading =
        jsonDecode(storage.preferences.getString('reading_settings')!);
    expect(reading['fontSize'], 24);
    expect(reading['lineHeight'], 1.1);
    expect(reading['storageFolder'], 'default');
    expect(() => validatedReading({'fontSize': double.nan}), returnsNormally);
  });
}
