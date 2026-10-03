import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../twitter/models/social_models.dart';

class MediaSaver {
  static const _channel = MethodChannel('com.review.x/media');
  static Future<void> save(SocialMedia media, String folder) async {
    final url = media.original;
    if (!safeMediaUrl(url)) throw const FormatException('不支持的媒体地址');
    final video = media.video != null;
    final uri = Uri.parse(url),
        format = Uri.parse(url).queryParameters['format'];
    final extension = video
        ? 'mp4'
        : format == 'png' || uri.path.toLowerCase().endsWith('.png')
            ? 'png'
            : format == 'webp' || uri.path.toLowerCase().endsWith('.webp')
                ? 'webp'
                : 'jpg';
    final mime = video
        ? 'video/mp4'
        : extension == 'jpg'
            ? 'image/jpeg'
            : 'image/$extension';
    final name = 'Review_X_${DateTime.now().microsecondsSinceEpoch}.$extension';
    final file = File(
        '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}$name');
    final dio = Dio(BaseOptions(
        followRedirects: false,
        maxRedirects: 0,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 2)));
    final cancel = CancelToken();
    try {
      await dio.download(url, file.path, cancelToken: cancel,
          onReceiveProgress: (received, total) {
        if (received > 512 * 1024 * 1024 || total > 512 * 1024 * 1024) {
          cancel.cancel('媒体文件超过 512 MiB');
        }
      });
      await _channel.invokeMethod('saveMedia', {
        'path': file.path,
        'name': name,
        'mime': mime,
        'folder': folder
            .replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')
            .substring(0, folder.length.clamp(0, 80))
      });
    } on DioException {
      throw StateError('媒体下载失败，请检查网络后重试');
    } finally {
      dio.close();
      if (await file.exists()) await file.delete();
    }
  }
}
