package com.review.x

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache

class ReviewApplication : Application(), ImageLoaderFactory {
    @OptIn(coil.annotation.ExperimentalCoilApi::class)
    override fun newImageLoader(): ImageLoader {
        val threshold = AppSettings(this).int("auto_clear_cache_threshold_mb", 200)
            .takeIf { it in AppSettings.cacheThresholds } ?: 200
        return ImageLoader.Builder(this)
            .okHttpClient { AppNetwork.http }
            .memoryCache { MemoryCache.Builder(this).maxSizePercent(.18).build() }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("image_cache"))
                    .maxSizeBytes(if (threshold == 0) Long.MAX_VALUE else threshold * 1024L * 1024)
                    .build()
            }
            .crossfade(false)
            .build()
    }
}
