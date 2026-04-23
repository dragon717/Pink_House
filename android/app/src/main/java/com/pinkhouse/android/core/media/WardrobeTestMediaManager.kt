package com.pinkhouse.android.core.media

import android.content.Context
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class WardrobeTestMedia(
    val assetPath: String,
    val displayName: String,
)

class WardrobeTestMediaManager(
    private val context: Context,
    private val wardrobeImageStore: WardrobeImageStore,
) {
    fun availableMedia(): List<WardrobeTestMedia> {
        return runCatching {
            context.assets
                .list(TEST_MEDIA_DIR)
                .orEmpty()
                .filter { it.isNotBlank() }
                .sorted()
                .map { fileName ->
                    WardrobeTestMedia(
                        assetPath = "$TEST_MEDIA_DIR/$fileName",
                        displayName = fileName.substringBeforeLast('.').replace('_', ' '),
                    )
                }
        }.getOrDefault(emptyList())
    }

    suspend fun importMedia(assetPath: String): String = withContext(Dispatchers.IO) {
        val assetName = assetPath.substringAfterLast('/')
        wardrobeImageStore.importStream(
            sourceName = assetName,
            openStream = { context.assets.open(assetPath) },
        )
    }

    suspend fun importAllMedia(): List<String> = withContext(Dispatchers.IO) {
        availableMedia().map { media -> importMedia(media.assetPath) }
    }

    suspend fun seedEmulatorPictures(): Int = withContext(Dispatchers.IO) {
        val targetDir = File(context.cacheDir, "wardrobe_test_media_export").apply { mkdirs() }
        var count = 0
        availableMedia().forEach { media ->
            val targetFile = File(targetDir, media.assetPath.substringAfterLast('/'))
            context.assets.open(media.assetPath).use { input ->
                targetFile.outputStream().use { output -> input.copyTo(output) }
            }
            count += 1
        }
        count
    }

    companion object {
        const val TEST_MEDIA_DIR = "wardrobe_test_media"
    }
}
