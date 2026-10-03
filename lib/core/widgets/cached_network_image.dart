import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

/// Reuses ExtendedImage's URL-keyed disk cache across ordinary app launches.
/// Android may reclaim its temporary cache, so images always keep a network
/// fallback and must not be treated as durable user files.
class CachedNetworkImage extends StatelessWidget {
  const CachedNetworkImage(
    this.url, {
    super.key,
    this.headers,
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
  });

  final String url;
  final Map<String, String>? headers;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return ExtendedImage.network(
      url,
      headers: headers,
      width: width,
      height: height,
      fit: fit,
      cache: true,
      loadStateChanged: errorBuilder == null
          ? null
          : (state) {
              if (state.extendedImageLoadState == LoadState.failed) {
                return errorBuilder!(
                  context,
                  state.lastException ?? StateError('图片加载失败'),
                  state.lastStack,
                );
              }
              return null;
            },
    );
  }
}
