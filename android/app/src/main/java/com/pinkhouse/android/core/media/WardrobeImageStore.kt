package com.pinkhouse.android.core.media

import android.content.Context
import android.net.Uri
import java.io.File
import java.io.InputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class WardrobeImageStore(
    private val context: Context,
) {
    private val imageDir: File by lazy {
        File(context.filesDir, "wardrobe_images").apply { mkdirs() }
    }

    suspend fun import(uri: Uri): String = withContext(Dispatchers.IO) {
        importStream(
            sourceName = uri.lastPathSegment.orEmpty(),
            openStream = {
                context.contentResolver.openInputStream(uri) ?: error("Cannot open selected image")
            },
        )
    }

    suspend fun importStream(
        sourceName: String,
        openStream: () -> InputStream,
    ): String = withContext(Dispatchers.IO) {
        val extension = sourceName.substringAfterLast('.', "jpg").lowercase()
        val safeExtension = extension.takeIf { it in setOf("jpg", "jpeg", "png", "webp") } ?: "jpg"
        val fileName = "wardrobe_${System.currentTimeMillis()}_${sourceName.hashCode()}.$safeExtension"
        val target = File(imageDir, fileName)
        openStream().use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        fileName
    }

    fun fileFor(fileName: String): File {
        return File(imageDir, fileName)
    }
}
