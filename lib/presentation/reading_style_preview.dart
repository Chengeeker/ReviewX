import 'package:flutter/material.dart';
import '../twitter/models/social_models.dart';
import 'post_card.dart';

class ReadingStylePreview extends StatelessWidget {
  const ReadingStylePreview({super.key});

  static final _post = SocialPost(
      id: 'reading-style-preview',
      author: const SocialUser(
          id: 'preview-author',
          name: 'Review X',
          handle: 'reviewx',
          verified: true),
      text: 'A quiet moment. #日常 https://example.com',
      translatedText: '记录生活中的片刻。#日常 https://example.com',
      source: 'Review X',
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      media: const [
        SocialMedia(
            preview: 'https://picsum.photos/id/1015/1200/500',
            width: 1200,
            height: 500),
      ],
      likes: 128,
      replies: 12,
      reposts: 24,
      views: 2048);

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant))),
        child: ClipRect(
          // Preserve timeline sizing; excess content is clipped, never scrolled.
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: IgnorePointer(child: PostCard(post: _post)),
          ),
        ),
      );
}
