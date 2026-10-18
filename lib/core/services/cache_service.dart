import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CacheService {
  CacheService._();

  static const thresholdKey = 'auto_clear_cache_threshold_mb';
  static const defaultThresholdMb = 200;
  static const thresholdsMb = [0, 50, 100, 200, 500, 1024, 2048];
  static const _channel = MethodChannel('com.review.x/cache');

  static Future<CacheBreakdown> getCacheStats() async {
    final stats = await _channel.invokeMapMethod<String, int>('getCacheStats');
    return CacheBreakdown(
      totalBytes: stats?['total'] ?? 0,
      imageBytes: stats?['images'] ?? 0,
      networkBytes: stats?['network'] ?? 0,
      systemBytes: stats?['system'] ?? 0,
    );
  }

  static Future<int> clearCache() async {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    final result = await _channel.invokeMapMethod<String, int>('clearCache');
    return result?['cleared'] ?? 0;
  }

  static Future<bool> checkAndAutoClearCache(int thresholdMb) async {
    if (thresholdMb <= 0) return false;
    final stats = await getCacheStats();
    if (stats.totalBytes < thresholdMb * 1024 * 1024) return false;
    await clearCache();
    return true;
  }
}

class CacheBreakdown {
  const CacheBreakdown({
    required this.totalBytes,
    required this.imageBytes,
    required this.networkBytes,
    required this.systemBytes,
  });

  static const empty = CacheBreakdown(
    totalBytes: 0,
    imageBytes: 0,
    networkBytes: 0,
    systemBytes: 0,
  );

  final int totalBytes;
  final int imageBytes;
  final int networkBytes;
  final int systemBytes;

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}
