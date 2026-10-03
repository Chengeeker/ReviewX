import 'social_models.dart';

bool safeLink(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      const ['https', 'http'].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

Map<String, dynamic> cardValues(dynamic card) {
  final legacy = object(object(card)['legacy'] ?? card);
  final values = legacy['binding_values'];
  if (values is Map) return object(values);
  return {
    for (final entry in array(values).map(object))
      '${entry['key']}': entry['value']
  };
}

class LinkCard {
  const LinkCard(this.title, this.description, this.url, this.image);
  final String title, description, url, image;
  static LinkCard? parse(dynamic card) {
    final values = cardValues(card);
    String text(String key) => '${object(values[key])['string_value'] ?? ''}';
    final url =
        text('card_url').isNotEmpty ? text('card_url') : text('vanity_url');
    if (!safeLink(url) || text('title').isEmpty) return null;
    final image = [
          'summary_photo_image_large',
          'photo_image_full_size_large',
          'thumbnail_image_original'
        ]
            .map((key) =>
                '${object(object(values[key])['image_value'])['url'] ?? ''}')
            .where(safeMediaUrl)
            .firstOrNull ??
        '';
    return LinkCard(text('title'), text('description'), url, image);
  }
}

class SocialPoll {
  const SocialPoll(this.choices, this.votes, this.endsAt, this.selected);
  final List<String> choices;
  final List<int> votes;
  final DateTime? endsAt;
  final int? selected;
  int get total => votes.fold(0, (a, b) => a + b);
  static SocialPoll? parse(dynamic card) {
    final values = cardValues(card);
    String text(String key) => '${object(values[key])['string_value'] ?? ''}';
    final choices = <String>[], votes = <int>[];
    for (var i = 1; i <= 4; i++) {
      if (text('choice${i}_label').isEmpty) continue;
      choices.add(text('choice${i}_label'));
      votes.add(count(text('choice${i}_count')).clamp(0, 1 << 53));
    }
    if (choices.length < 2) return null;
    return SocialPoll(
        choices,
        votes,
        DateTime.tryParse(text('end_datetime_utc')),
        int.tryParse(text('selected_choice')));
  }
}

class ArticleBlock {
  const ArticleBlock(
      this.text, this.type, this.styles, this.links, this.media, this.caption);
  final String text, type, caption;
  final List<Map<String, dynamic>> styles, links;
  final List<SocialMedia> media;
}

class SocialArticle {
  const SocialArticle(
      {required this.id,
      required this.title,
      this.preview = '',
      this.cover,
      this.blocks = const []});
  final String id, title, preview;
  final SocialMedia? cover;
  final List<ArticleBlock> blocks;
  bool get full => blocks.isNotEmpty;

  /// Feed snapshots retain the card preview only; opening an article refreshes
  /// its full server-backed body through the existing article endpoint.
  Map<String, dynamic> toCachePreviewJson() => {
        'id': id,
        'title': title,
        'preview':
            preview.length <= 1200 ? preview : preview.substring(0, 1200),
        'cover': cover?.toCacheJson(),
      };

  static SocialArticle? fromCachePreviewJson(dynamic value) {
    final article = object(value);
    final title = article['title'];
    if (title is! String || title.trim().isEmpty) return null;
    return SocialArticle(
      id: '${article['id'] ?? ''}',
      title: title.length <= 300 ? title : title.substring(0, 300),
      preview: article['preview'] is String
          ? ((article['preview'] as String).length <= 1200
              ? article['preview'] as String
              : (article['preview'] as String).substring(0, 1200))
          : '',
      cover: SocialMedia.fromCacheJson(article['cover']),
    );
  }

  static SocialMedia? _media(dynamic value) {
    final info = object(object(value)['media_info']);
    final previewInfo = object(info['preview_image']);
    final preview =
        '${info['original_img_url'] ?? previewInfo['original_img_url'] ?? ''}';
    if (!safeMediaUrl(preview)) return null;
    final variants = array(info['variants'])
        .map(object)
        .where((v) =>
            v['content_type'] == 'video/mp4' && safeMediaUrl('${v['url']}'))
        .toList()
      ..sort((a, b) => count(b['bit_rate']).compareTo(count(a['bit_rate'])));
    return SocialMedia(
        preview: preview,
        video: variants.isEmpty ? null : '${variants.first['url']}',
        width: count(
            info['original_img_width'] ?? previewInfo['original_img_width']),
        height: count(
            info['original_img_height'] ?? previewInfo['original_img_height']));
  }

  static SocialArticle? parse(dynamic value) {
    final article = object(value);
    if (article['title'] is! String) return null;
    final state = object(article['content_state']),
        entities = <String, Map<String, dynamic>>{};
    if (state['entityMap'] is Map) {
      object(state['entityMap'])
          .forEach((key, value) => entities[key] = object(value));
    } else {
      for (final entry in array(state['entityMap']).map(object)) {
        entities['${entry['key']}'] = object(entry['value']);
      }
    }
    final media = {
      for (final entry in array(article['media_entities']).map(object))
        '${entry['media_id']}': _media(entry)
    };
    final blocks = <ArticleBlock>[];
    for (final block in array(state['blocks']).map(object)) {
      final images = <SocialMedia>[], links = <Map<String, dynamic>>[];
      var caption = '';
      for (final range in array(block['entityRanges']).map(object)) {
        final entity = entities['${range['key']}'] ?? {},
            data = object(entity['data']);
        if (entity['type'] == 'LINK' && safeLink('${data['url']}')) {
          links.add({...range, 'url': data['url']});
        }
        if (entity['type'] == 'MEDIA') {
          caption = '${data['caption'] ?? ''}';
          for (final item in array(data['mediaItems']).map(object)) {
            final image = media['${item['mediaId']}'];
            if (image != null) images.add(image);
          }
        }
      }
      for (final link in array(object(block['data'])['urls']).map(object)) {
        if (safeLink('${link['text']}')) {
          links.add({
            'offset': count(link['fromIndex']),
            'length': count(link['toIndex']) - count(link['fromIndex']),
            'url': link['text']
          });
        }
      }
      blocks.add(ArticleBlock(
          '${block['text'] ?? ''}',
          '${block['type'] ?? 'unstyled'}',
          array(block['inlineStyleRanges']).map(object).toList(),
          links,
          images,
          caption));
    }
    return SocialArticle(
        id: '${article['rest_id'] ?? ''}',
        title: article['title'],
        preview: '${article['preview_text'] ?? ''}',
        cover: _media(article['cover_media']),
        blocks: blocks);
  }
}

/// Walk only official timeline items, including module items and replacements.
List<Map<String, dynamic>> timelineItems(dynamic timeline) {
  final result = <Map<String, dynamic>>[];
  void add(dynamic value) {
    final content = object(value);
    if (content['promotedMetadata'] != null) return;
    if (content['cursorType'] != null) {
      result.add(content);
      return;
    }
    final item = object(content['itemContent'] ?? content);
    if (item['promotedMetadata'] == null && item['itemType'] != null) {
      result.add(item);
    }
    for (final module in array(content['items'])) {
      add(object(module)['item']);
    }
  }

  for (final instruction
      in array(object(timeline)['instructions']).map(object)) {
    for (final entry in array(instruction['entries']).map(object)) {
      add(entry['content']);
    }
    if (instruction['entry'] != null) {
      add(object(instruction['entry'])['content']);
    }
    for (final item in array(instruction['moduleItems'])) {
      add(object(item)['item']);
    }
  }
  return result;
}

class UserPage {
  const UserPage(this.users, this.cursor);
  final List<SocialUser> users;
  final String? cursor;
  static UserPage parse(dynamic timeline) {
    final items = timelineItems(timeline), users = <String, SocialUser>{};
    String? cursor;
    for (final item in items) {
      if (item['cursorType'] == 'Bottom') cursor = item['value'] as String?;
      final user = SocialUser.parse(object(item['user_results'])['result']);
      if (user != null) users[user.id] = user;
    }
    return UserPage(users.values.toList(), cursor);
  }
}

class SocialNotification {
  const SocialNotification(
      {required this.id,
      required this.message,
      this.url = '',
      this.icon = '',
      this.actors = const [],
      this.posts = const [],
      this.createdAt});
  final String id, message, url, icon;
  final List<SocialUser> actors;
  final List<SocialPost> posts;
  final DateTime? createdAt;
}

class NotificationPageData {
  const NotificationPageData(this.notifications, this.cursor, this.topCursor);
  final List<SocialNotification> notifications;
  final String? cursor, topCursor;
  static NotificationPageData parse(dynamic timeline) {
    final notifications = <String, SocialNotification>{};
    String? cursor, top;
    for (final item in timelineItems(timeline)) {
      if (item['cursorType'] == 'Bottom') cursor = item['value'] as String?;
      if (item['cursorType'] == 'Top') top = item['value'] as String?;
      final post = SocialPost.parse(object(item['tweet_results'])['result']);
      if (post != null) {
        notifications[post.id] = SocialNotification(
            id: post.id,
            message: '${post.author.name} 的帖子',
            posts: [post],
            createdAt: post.createdAt);
      } else if (item['itemType'] == 'TimelineNotification') {
        final template = object(item['template']);
        final actors = array(template['from_users'])
            .map((u) =>
                SocialUser.parse(object(object(u)['user_results'])['result']))
            .whereType<SocialUser>()
            .toList();
        final posts = array(template['target_objects'])
            .map((p) =>
                SocialPost.parse(object(object(p)['tweet_results'])['result']))
            .whereType<SocialPost>()
            .toList();
        final id = '${item['id'] ?? ''}', millis = count(item['timestamp_ms']);
        if (id.isEmpty) continue;
        notifications[id] = SocialNotification(
            id: id,
            message: '${object(item['rich_message'])['text'] ?? ''}',
            url: '${object(item['notification_url'])['url'] ?? ''}',
            icon: '${item['notification_icon'] ?? ''}',
            actors: actors,
            posts: posts,
            createdAt: millis == 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(millis));
      }
    }
    return NotificationPageData(notifications.values.toList(), cursor, top);
  }
}
