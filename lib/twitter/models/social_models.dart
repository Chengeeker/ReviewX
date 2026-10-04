import 'package:intl/intl.dart';
import 'content_models.dart';

Map<String, dynamic> object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<dynamic> array(dynamic value) => value is List ? value : const [];
int count(dynamic value) => int.tryParse('$value') ?? 0;
String _cacheText(dynamic value, {int limit = 20000}) {
  final text = value is String ? value : '';
  return text.length <= limit ? text : text.substring(0, limit);
}

class SocialUser {
  const SocialUser(
      {required this.id,
      required this.name,
      required this.handle,
      this.avatar = '',
      this.banner = '',
      this.description = '',
      this.followers = 0,
      this.following = 0,
      this.verified = false,
      this.isFollowing = false,
      this.followedBy = false,
      this.protected = false,
      this.location = '',
      this.website = '',
      this.postsCount = 0,
      this.createdAt = '',
      this.followRequested = false,
      this.knownCounts = const {'followers', 'following', 'postsCount'}});
  final String id, name, handle, avatar, banner, description;
  final int followers, following;
  final bool verified;
  final bool isFollowing, followedBy, protected;
  final String location, website, createdAt;
  final int postsCount;
  final bool followRequested;
  final Set<String> knownCounts;

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'name': name,
        'handle': handle,
        'avatar': avatar,
        'banner': banner,
        'description': description,
        'knownCounts': knownCounts.toList(),
        'followers': followers,
        'following': following,
        'verified': verified,
        'isFollowing': isFollowing,
        'followedBy': followedBy,
        'protected': protected,
        'location': location,
        'website': website,
        'postsCount': postsCount,
        'createdAt': createdAt,
        'followRequested': followRequested,
      };

  static SocialUser? fromCacheJson(dynamic value) {
    final user = object(value);
    final id = _cacheText(user['id'], limit: 32);
    final handle = _cacheText(user['handle'], limit: 100);
    if (!RegExp(r'^\d+$').hasMatch(id) || handle.isEmpty) return null;
    final avatar = _cacheText(user['avatar'], limit: 2048);
    final banner = _cacheText(user['banner'], limit: 2048);
    final website = _cacheText(user['website'], limit: 2048);
    final websiteUri = Uri.tryParse(website);
    return SocialUser(
      id: id,
      handle: handle,
      name: _cacheText(user['name'], limit: 200),
      avatar: safeMediaUrl(avatar) ? avatar : '',
      banner: safeMediaUrl(banner) ? banner : '',
      description: _cacheText(user['description'], limit: 1200),
      knownCounts: user['knownCounts'] is List
          ? array(user['knownCounts'])
              .whereType<String>()
              .where(const {'followers', 'following', 'postsCount'}.contains)
              .toSet()
          : const {'followers', 'following', 'postsCount'},
      followers: count(user['followers']).clamp(0, 1 << 53),
      following: count(user['following']).clamp(0, 1 << 53),
      verified: user['verified'] == true,
      isFollowing: user['isFollowing'] == true,
      followedBy: user['followedBy'] == true,
      protected: user['protected'] == true,
      location: _cacheText(user['location'], limit: 200),
      website: websiteUri != null &&
              const {'http', 'https'}.contains(websiteUri.scheme) &&
              websiteUri.host.isNotEmpty &&
              websiteUri.userInfo.isEmpty
          ? website
          : '',
      postsCount: count(user['postsCount']).clamp(0, 1 << 53),
      createdAt: _cacheText(user['createdAt'], limit: 80),
      followRequested: user['followRequested'] == true,
    );
  }

  /// Missing statistics are unknown, while an explicit zero remains authoritative.
  SocialUser preservingCounts(SocialUser? previous) {
    if (previous == null || previous.id != id) return this;
    return SocialUser(
        id: id,
        name: name,
        handle: handle,
        avatar: avatar,
        banner: banner,
        description: description,
        verified: verified,
        isFollowing: isFollowing,
        followedBy: followedBy,
        protected: protected,
        location: location,
        website: website,
        createdAt: createdAt,
        followRequested: followRequested,
        followers:
            knownCounts.contains('followers') ? followers : previous.followers,
        following:
            knownCounts.contains('following') ? following : previous.following,
        postsCount: knownCounts.contains('postsCount')
            ? postsCount
            : previous.postsCount,
        knownCounts: {...previous.knownCounts, ...knownCounts});
  }

  static SocialUser? parse(dynamic value) {
    final user = object(value), legacy = object(object(value)['legacy']);
    final core = object(user['core']);
    final relationships = object(user['relationship_counts']);
    final tweets = object(user['tweet_counts']);
    final id = '${user['rest_id'] ?? legacy['id_str'] ?? ''}';
    final handle = '${core['screen_name'] ?? legacy['screen_name'] ?? ''}';
    if (id.isEmpty || handle.isEmpty) return null;
    return SocialUser(
        id: id,
        name: '${core['name'] ?? legacy['name'] ?? handle}',
        handle: handle,
        avatar:
            '${object(user['avatar'])['image_url'] ?? legacy['profile_image_url_https'] ?? ''}'
                .replaceAll('_normal.', '_bigger.'),
        banner:
            '${object(user['banner'])['image_url'] ?? legacy['profile_banner_url'] ?? ''}',
        description:
            '${object(user['profile_bio'])['description'] ?? object(user['profile_description'])['description'] ?? legacy['description'] ?? ''}',
        followers:
            count(relationships['followers'] ?? legacy['followers_count']),
        following: count(relationships['following'] ?? legacy['friends_count']),
        knownCounts: {
          if (relationships['followers'] != null ||
              legacy['followers_count'] != null)
            'followers',
          if (relationships['following'] != null ||
              legacy['friends_count'] != null)
            'following',
          if (tweets['tweets'] != null || legacy['statuses_count'] != null)
            'postsCount',
        },
        isFollowing: (object(user['relationship_perspectives'])['following'] ??
                legacy['following']) ==
            true,
        followedBy: (object(user['relationship_perspectives'])['followed_by'] ??
                legacy['followed_by']) ==
            true,
        protected:
            (object(user['privacy'])['protected'] ?? legacy['protected']) ==
                true,
        location:
            '${object(user['location'])['location'] ?? legacy['location'] ?? ''}',
        website:
            '${object(user['website'])['url'] ?? object(array(object(object(legacy['entities'])['url'])['urls']).firstOrNull)['expanded_url'] ?? legacy['url'] ?? ''}',
        postsCount: count(tweets['tweets'] ?? legacy['statuses_count']),
        followRequested:
            (user['follow_request_sent'] ?? legacy['follow_request_sent']) ==
                true,
        createdAt: '${core['created_at'] ?? legacy['created_at'] ?? ''}',
        verified:
            user['is_blue_verified'] == true || legacy['verified'] == true);
  }
}

class TrendingTopic {
  const TrendingTopic({
    required this.name,
    this.description = '',
    this.metaDescription = '',
  });

  final String name;
  final String description;
  final String metaDescription;

  static List<TrendingTopic> parseGuide(dynamic response) {
    final timeline = object(object(response)['timeline']);
    final topics = <String, TrendingTopic>{};
    void readTrend(dynamic value) {
      final trend = object(value);
      final name = '${trend['name'] ?? trend['trend_name'] ?? ''}'.trim();
      if (name.isEmpty) return;
      final metadata =
          object(trend['trend_metadata'] ?? trend['trendMetadata']);
      topics.putIfAbsent(
        name.toLowerCase(),
        () => TrendingTopic(
          name: name,
          description: '${trend['description'] ?? ''}'.trim(),
          metaDescription:
              '${trend['metaDescription'] ?? trend['meta_description'] ?? metadata['metaDescription'] ?? ''}'
                  .trim(),
        ),
      );
    }

    void readModule(dynamic value) {
      final module = object(value);
      for (final item in array(module['items'])) {
        final entry = object(item);
        final itemContent = object(object(entry['item'])['content']);
        readTrend(itemContent['trend']);
      }
    }

    for (final instruction in array(timeline['instructions']).map(object)) {
      for (final entry in array(object(instruction['addEntries'])['entries'])) {
        final content = object(object(entry)['content']);
        readModule(content['timelineModule']);
        readTrend(object(object(content['item'])['content'])['trend']);
      }
      for (final entry in array(instruction['entries'])) {
        final content = object(object(entry)['content']);
        readModule(content['timelineModule']);
        readTrend(object(object(content['item'])['content'])['trend']);
      }
      readModule(instruction['timelineModule']);
      for (final item in array(instruction['moduleItems'])) {
        readTrend(object(object(object(item)['item'])['content'])['trend']);
      }
    }
    return topics.values.toList(growable: false);
  }
}

class SocialMedia {
  const SocialMedia(
      {required this.preview,
      this.video,
      this.videoQualities = const {},
      this.width = 0,
      this.height = 0,
      this.alt = ''});
  final String preview;
  final String? video;
  final Map<String, String> videoQualities;
  final int width, height;
  final String alt;

  Map<String, dynamic> toCacheJson() => {
        'preview': preview,
        'video': video,
        'videoQualities': videoQualities,
        'width': width,
        'height': height,
        'alt': alt,
      };

  static SocialMedia? fromCacheJson(dynamic value) {
    final media = object(value);
    final preview = _cacheText(media['preview'], limit: 2048);
    final video = _cacheText(media['video'], limit: 4096);
    if (!safeMediaUrl(preview)) return null;
    return SocialMedia(
      preview: preview,
      video: safeMediaUrl(video) ? video : null,
      videoQualities: Map.fromEntries(object(media['videoQualities'])
          .entries
          .take(12)
          .where((entry) => entry.value is String && safeMediaUrl(entry.value))
          .map((entry) => MapEntry(
              _cacheText(entry.key, limit: 40), entry.value as String))),
      width: count(media['width']).clamp(0, 100000),
      height: count(media['height']).clamp(0, 100000),
      alt: _cacheText(media['alt'], limit: 2000),
    );
  }

  String get original =>
      video ??
      Uri.parse(preview).replace(queryParameters: {
        ...Uri.parse(preview).queryParameters,
        'name': 'orig'
      }).toString();
  static SocialMedia? parse(dynamic value) {
    final media = object(value);
    final preview = '${media['media_url_https'] ?? ''}';
    if (!safeMediaUrl(preview)) return null;
    final variants = array(object(media['video_info'])['variants'])
        .map(object)
        .where((v) =>
            v['content_type'] == 'video/mp4' && safeMediaUrl('${v['url']}'))
        .toList()
      ..sort((a, b) => count(b['bitrate']).compareTo(count(a['bitrate'])));
    final size = object(media['original_info']);
    final qualities = <String, String>{};
    for (final variant in variants.take(12)) {
      final url = '${variant['url']}';
      final resolution =
          RegExp(r'/(\d+)x(\d+)/').firstMatch(Uri.parse(url).path);
      final label = resolution == null
          ? '${(count(variant['bitrate']) / 1000).round()} kbps'
          : '${[
              int.parse(resolution[1]!),
              int.parse(resolution[2]!)
            ].reduce((a, b) => a < b ? a : b)}p';
      qualities.putIfAbsent(label, () => url);
    }
    return SocialMedia(
        preview: preview,
        video: variants.isEmpty ? null : '${variants.first['url']}',
        videoQualities: qualities,
        alt: '${media['ext_alt_text'] ?? ''}',
        width: count(size['width']),
        height: count(size['height']));
  }
}

bool safeMediaUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      (uri.host == 'pbs.twimg.com' || uri.host == 'video.twimg.com');
}

class SocialPost {
  const SocialPost(
      {required this.id,
      required this.author,
      required this.text,
      this.translatedText = '',
      this.createdAt,
      this.media = const [],
      this.likes = 0,
      this.reposts = 0,
      this.replies = 0,
      this.liked = false,
      this.reposted = false,
      this.quote,
      this.repostedBy,
      this.article,
      this.linkCard,
      this.poll,
      this.views = 0,
      this.source = '',
      this.sensitive = false,
      this.replyToHandle,
      this.replyToId,
      this.conversationId,
      this.bookmarked = false});
  final String id, text, translatedText;
  final SocialUser author;
  final DateTime? createdAt;
  final List<SocialMedia> media;
  final int likes, reposts, replies;
  final bool liked, reposted;
  final SocialPost? quote;
  final String? repostedBy;
  final SocialArticle? article;
  final LinkCard? linkCard;
  final SocialPoll? poll;
  final int views;
  final String source;
  final bool sensitive;
  final String? replyToHandle;
  final String? replyToId, conversationId;
  final bool bookmarked;

  Map<String, dynamic> toCacheJson({int depth = 0}) => {
        'id': id,
        'author': author.toCacheJson(),
        'text': _cacheText(text, limit: 50000),
        'translatedText': _cacheText(translatedText, limit: 50000),
        'createdAt': createdAt?.toIso8601String(),
        'media': media.take(4).map((item) => item.toCacheJson()).toList(),
        'likes': likes,
        'reposts': reposts,
        'replies': replies,
        'liked': liked,
        'reposted': reposted,
        'quote': depth < 1 ? quote?.toCacheJson(depth: depth + 1) : null,
        'repostedBy': repostedBy,
        'article': article?.toCachePreviewJson(),
        'linkCard': linkCard == null
            ? null
            : {
                'title': linkCard!.title,
                'description': linkCard!.description,
                'url': linkCard!.url,
                'image': linkCard!.image,
              },
        'poll': poll == null
            ? null
            : {
                'choices': poll!.choices,
                'votes': poll!.votes,
                'endsAt': poll!.endsAt?.toIso8601String(),
                'selected': poll!.selected,
              },
        'views': views,
        'source': _cacheText(source, limit: 300),
        'sensitive': sensitive,
        'replyToHandle': replyToHandle,
        'replyToId': replyToId,
        'conversationId': conversationId,
        'bookmarked': bookmarked,
      };

  static SocialPost? fromCacheJson(dynamic value, {int depth = 0}) {
    if (depth > 1) return null;
    final post = object(value);
    final id = _cacheText(post['id'], limit: 32);
    final author = SocialUser.fromCacheJson(post['author']);
    if (!RegExp(r'^\d+$').hasMatch(id) || author == null) return null;
    final createdAt = DateTime.tryParse('${post['createdAt'] ?? ''}');
    final quote = depth < 1
        ? SocialPost.fromCacheJson(post['quote'], depth: depth + 1)
        : null;
    return SocialPost(
      id: id,
      author: author,
      text: _cacheText(post['text'], limit: 50000),
      translatedText: _cacheText(post['translatedText'], limit: 50000),
      createdAt: createdAt,
      media: array(post['media'])
          .take(4)
          .map(SocialMedia.fromCacheJson)
          .whereType<SocialMedia>()
          .toList(growable: false),
      likes: count(post['likes']).clamp(0, 1 << 53),
      reposts: count(post['reposts']).clamp(0, 1 << 53),
      replies: count(post['replies']).clamp(0, 1 << 53),
      liked: post['liked'] == true,
      reposted: post['reposted'] == true,
      quote: quote,
      repostedBy: post['repostedBy'] is String
          ? _cacheText(post['repostedBy'], limit: 200)
          : null,
      article: SocialArticle.fromCachePreviewJson(post['article']),
      linkCard: _cacheLinkCard(post['linkCard']),
      poll: _cachePoll(post['poll']),
      views: count(post['views']).clamp(0, 1 << 53),
      source: _cacheText(post['source'], limit: 300),
      sensitive: post['sensitive'] == true,
      replyToHandle: post['replyToHandle'] is String
          ? _cacheText(post['replyToHandle'], limit: 100)
          : null,
      bookmarked: post['bookmarked'] == true,
      replyToId: post['replyToId'] is String
          ? _cacheText(post['replyToId'], limit: 32)
          : null,
      conversationId: post['conversationId'] is String
          ? _cacheText(post['conversationId'], limit: 32)
          : null,
    );
  }

  static LinkCard? _cacheLinkCard(dynamic value) {
    final card = object(value);
    final url = _cacheText(card['url'], limit: 2048);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final image = _cacheText(card['image'], limit: 2048);
    return LinkCard(
      _cacheText(card['title'], limit: 300),
      _cacheText(card['description'], limit: 1000),
      url,
      safeMediaUrl(image) ? image : '',
    );
  }

  static SocialPoll? _cachePoll(dynamic value) {
    final poll = object(value);
    final choices = array(poll['choices'])
        .take(4)
        .map((item) => _cacheText(item, limit: 300))
        .toList(growable: false);
    if (choices.length < 2) return null;
    final votes = array(poll['votes'])
        .take(choices.length)
        .map((item) => count(item).clamp(0, 1 << 53))
        .toList();
    while (votes.length < choices.length) {
      votes.add(0);
    }
    return SocialPoll(
      choices,
      votes,
      DateTime.tryParse('${poll['endsAt'] ?? ''}'),
      poll['selected'] is num ? (poll['selected'] as num).toInt() : null,
    );
  }

  String get url => 'https://x.com/${author.handle}/status/$id';
  SocialPost withActions({bool? liked, bool? reposted, bool? bookmarked}) =>
      SocialPost(
          id: id,
          author: author,
          text: text,
          translatedText: translatedText,
          createdAt: createdAt,
          media: media,
          likes: (likes +
                  (liked == null || liked == this.liked
                      ? 0
                      : liked
                          ? 1
                          : -1))
              .clamp(0, 1 << 53),
          reposts: (reposts +
                  (reposted == null || reposted == this.reposted
                      ? 0
                      : reposted
                          ? 1
                          : -1))
              .clamp(0, 1 << 53),
          replies: replies,
          liked: liked ?? this.liked,
          reposted: reposted ?? this.reposted,
          quote: quote,
          article: article,
          linkCard: linkCard,
          poll: poll,
          views: views,
          source: source,
          sensitive: sensitive,
          replyToHandle: replyToHandle,
          replyToId: replyToId,
          conversationId: conversationId,
          bookmarked: bookmarked ?? this.bookmarked,
          repostedBy: repostedBy);
  static SocialPost? parse(dynamic value, {int depth = 0, String? repostedBy}) {
    if (depth > 3) return null;
    var post = object(value);
    if (post['__typename'] == 'TweetWithVisibilityResults') {
      post = object(post['tweet']);
    }
    final legacy = object(post['legacy']);
    final author = SocialUser.parse(
        object(object(post['core'])['user_results'])['result']);
    final id = '${post['rest_id'] ?? legacy['id_str'] ?? ''}';
    if (id.isEmpty || author == null) return null;
    final original = object(legacy['retweeted_status_result'])['result'];
    if (original != null) {
      return parse(original, depth: depth + 1, repostedBy: author.name);
    }
    final note = object(
        object(object(post['note_tweet'])['note_tweet_results'])['result']);
    var text = '${note['text'] ?? legacy['full_text'] ?? ''}';
    final entities = object(note['entity_set'] ?? legacy['entities']);
    for (final url in array(entities['urls']).map(object)) {
      if (url['url'] is String && url['expanded_url'] is String) {
        text = text.replaceAll(url['url'], url['expanded_url']);
      }
    }
    final media = array(object(legacy['extended_entities'])['media'] ??
        object(legacy['entities'])['media']);
    for (final item in media.map(object)) {
      if (item['url'] is String) text = text.replaceAll(item['url'], '');
    }
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    final translationState =
        object(post['grok_translated_post_with_availability']);
    final translationData = object(translationState['data']);
    final destinationLanguage =
        '${translationData['destination_language'] ?? ''}'
            .trim()
            .toLowerCase()
            .replaceAll('_', '-');
    var translatedText = '';
    if (translationState['is_available'] == true &&
        const {'zh', 'zh-cn', 'zh-hans', 'zh-hans-cn'}
            .contains(destinationLanguage)) {
      translatedText = '${translationData['translation'] ?? ''}'.trim();
      for (final url
          in array(object(translationData['entities'])['urls']).map(object)) {
        if (url['url'] is String && url['expanded_url'] is String) {
          translatedText =
              translatedText.replaceAll(url['url'], url['expanded_url']);
        }
      }
      translatedText = translatedText
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .trim();
    }
    DateTime? date;
    try {
      final value = '${legacy['created_at']}';
      final zone = RegExp(r' ([+-])(\d{2})(\d{2}) ').firstMatch(value);
      if (zone != null) {
        final clean = value.replaceRange(zone.start, zone.end, ' ');
        final offset = (int.parse(zone[2]!) * 60 + int.parse(zone[3]!)) *
            (zone[1] == '+' ? 1 : -1);
        date = DateFormat('EEE MMM dd HH:mm:ss yyyy', 'en_US')
            .parseUtc(clean)
            .subtract(Duration(minutes: offset));
      }
    } catch (_) {}
    return SocialPost(
        id: id,
        author: author,
        text: text.trim(),
        translatedText: translatedText,
        createdAt: date,
        media: media.map(SocialMedia.parse).whereType<SocialMedia>().toList(),
        likes: count(legacy['favorite_count']),
        reposts: count(legacy['retweet_count']),
        replies: count(legacy['reply_count']),
        liked: legacy['favorited'] == true,
        reposted: legacy['retweeted'] == true,
        article: SocialArticle.parse(
            object(object(post['article'])['article_results'])['result']),
        linkCard: LinkCard.parse(post['card']),
        poll: SocialPoll.parse(post['card']),
        views: count(object(post['views'])['count']),
        source: '${post['source'] ?? legacy['source'] ?? ''}'
            .replaceAll(RegExp('<[^>]*>'), ''),
        sensitive: legacy['possibly_sensitive'] == true,
        replyToHandle: legacy['in_reply_to_screen_name'] as String?,
        replyToId: legacy['in_reply_to_status_id_str'] as String?,
        conversationId: legacy['conversation_id_str'] as String?,
        bookmarked: legacy['bookmarked'] == true,
        repostedBy: repostedBy,
        quote: parse(object(post['quoted_status_result'])['result'],
            depth: depth + 1));
  }
}

class PostPage {
  const PostPage(this.posts, this.cursor);
  final List<SocialPost> posts;
  final String? cursor;

  /// Parse only timeline entries, never recursively collect quoted tweets as rows.
  static PostPage parse(dynamic timeline) {
    final posts = <SocialPost>[], seen = <String>{};
    String? cursor;
    void item(dynamic value) {
      final content = object(value);
      if (content['cursorType'] == 'Bottom') {
        cursor = content['value'] as String?;
      }
      if (content['promotedMetadata'] != null) return;
      final data = object(content['itemContent'] ?? content);
      if (data['promotedMetadata'] != null) return;
      final post = SocialPost.parse(object(data['tweet_results'])['result']);
      if (post != null && seen.add(post.id)) posts.add(post);
      for (final module in array(content['items'])) {
        item(object(module)['item']);
      }
    }

    for (final instruction
        in array(object(timeline)['instructions']).map(object)) {
      for (final entry in array(instruction['entries']).map(object)) {
        item(entry['content']);
      }
      final entry = object(instruction['entry']);
      if (entry.isNotEmpty) item(entry['content']);
      for (final module in array(instruction['moduleItems'])) {
        item(object(module)['item']);
      }
    }
    return PostPage(posts, cursor?.isEmpty == true ? null : cursor);
  }
}
