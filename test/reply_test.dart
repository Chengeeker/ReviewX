import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/presentation/post_card.dart';
import 'package:review_x/presentation/timeline_page.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/app_controller.dart';
import 'package:review_x/twitter/models/social_models.dart';

const rootUser = SocialUser(id: '1', name: 'Root', handle: 'root');
const replyUser = SocialUser(id: '2', name: 'First', handle: 'first');
const root = SocialPost(
    id: '10', author: rootUser, text: 'original', conversationId: '10');
const firstReply = SocialPost(
    id: '20',
    author: replyUser,
    text: 'first reply',
    replyToId: '10',
    replyToHandle: 'root',
    conversationId: '10');
const nestedReply = SocialPost(
    id: '30',
    author: rootUser,
    text: 'nested reply',
    replyToId: '20',
    replyToHandle: 'first',
    conversationId: '10');

Map<String, dynamic> response(String text, {String? cursor}) => {
      'threaded_conversation_with_injections_v2': {
        'instructions': [
          {
            'entries': [
              {
                'content': {
                  'itemContent': {
                    'tweet_results': {
                      'result': {
                        'rest_id': '40',
                        'core': {
                          'user_results': {
                            'result': {
                              'rest_id': '2',
                              'core': {'name': 'First', 'screen_name': 'first'}
                            }
                          }
                        },
                        'legacy': {
                          'full_text': text,
                          'conversation_id_str': '10',
                          'in_reply_to_status_id_str': '10',
                          'in_reply_to_screen_name': 'root'
                        },
                      }
                    }
                  }
                }
              },
              if (cursor != null)
                {
                  'content': {'cursorType': 'Bottom', 'value': cursor}
                },
            ]
          },
        ]
      },
    };

class PendingReplies extends TwitterClient {
  final variables = <Map<String, dynamic>>[];
  final pending = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> call(
      String operation, Map<String, dynamic> values) {
    expect(operation, 'TweetDetail');
    variables.add(Map.of(values));
    final result = Completer<Map<String, dynamic>>();
    pending.add(result);
    return result.future;
  }
}

void main() {
  testWidgets('home connects a reply chain without joining unrelated posts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    const unrelated = SocialPost(
        id: '50', author: rootUser, text: 'unrelated', conversationId: '10');
    const sibling = SocialPost(
        id: '60',
        author: replyUser,
        text: 'another reply',
        replyToId: '10',
        replyToHandle: 'root',
        conversationId: '10');
    const rows = [root, firstReply, nestedReply, unrelated, sibling];
    await tester.pumpWidget(ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: MaterialApp(
          home: Scaffold(
              body: TimelinePage(
        initial: rows,
        load: (_) async => const PostPage(rows, null),
      ))),
    ));
    await tester.pumpAndSettle();
    final cards = tester.widgetList<PostCard>(find.byType(PostCard)).toList();
    expect(cards[0].connectedAbove, isFalse);
    expect(cards[0].connectedBelow, isTrue);
    expect(cards[1].connectedAbove, isTrue);
    expect(cards[1].connectedBelow, isTrue);
    expect(cards[2].connectedAbove, isTrue);
    expect(cards[2].connectedBelow, isFalse);
    expect(cards[3].connectedAbove || cards[3].connectedBelow, isFalse);
    expect(cards[4].connectedAbove || cards[4].connectedBelow, isFalse);
    expect(tester.getTopLeft(find.text('original')).dx, 28);
    expect(tester.getTopLeft(find.text('unrelated')).dx, 12);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'nested replies show actual parent context and bounded indentation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    await tester.pumpWidget(ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: MaterialApp(
          home: Scaffold(
              body: TimelinePage(
        conversationRoot: root,
        header: const PostCard(post: root, detail: true),
        initial: const [firstReply, nestedReply],
        load: (_) async => const PostPage([firstReply, nestedReply], null),
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('回复 @root'), findsOneWidget);
    expect(find.text('回复 @first'), findsOneWidget);
    expect(find.text('first reply'), findsNWidgets(2));
    final cards = tester.widgetList<PostCard>(find.byType(PostCard)).toList();
    expect(cards.last.replyParent?.id, firstReply.id);
    final first = find.byWidgetPredicate(
        (widget) => widget is PostCard && widget.post.id == '20');
    final nested = find.byWidgetPredicate(
        (widget) => widget is PostCard && widget.post.id == '30');
    expect(tester.getTopLeft(nested).dx - tester.getTopLeft(first).dx, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sorting discards stale requests and resets the pagination cursor',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final client = PendingReplies();
    final controller = AppController(client: client);
    await tester.pumpWidget(ProviderScope(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      appControllerProvider.overrideWith((ref) => controller),
    ], child: const MaterialApp(home: PostDetailPage(post: root))));
    await tester.pump();
    await tester.tap(find.byTooltip('回复排序'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('最近'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.variables[1]['rankingMode'], 'Recency');
    expect(client.variables[1].containsKey('cursor'), isFalse);
    client.pending[1].complete(response('recent reply', cursor: 'recent-next'));
    await tester.pumpAndSettle();
    client.pending[0].complete(response('stale reply', cursor: 'old-next'));
    await tester.pumpAndSettle();
    expect(find.text('recent reply'), findsOneWidget);
    expect(find.text('stale reply'), findsNothing);
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    expect(client.variables.last['cursor'], 'recent-next');
    expect(client.variables.last['rankingMode'], 'Recency');
    client.pending.last.complete(response('recent reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('回复排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('喜欢'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.variables.last['rankingMode'], 'Likes');
    expect(client.variables.last.containsKey('cursor'), isFalse);
    client.pending.last.complete(response('liked reply'));
    await tester.pumpAndSettle();
    expect(find.text('liked reply'), findsOneWidget);
    expect(find.text('recent reply'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
