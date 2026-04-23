package com.pinkhouse.android.core.media

import android.content.Context
import android.net.Uri
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class WardrobeImageStore(
    private val context: Context,
) {
    private val imageDir: File by lazy {
        File(context.filesDir, "wardrobe_images").apply { mkdirs() }
    }

    suspend fun import(uri: Uri): String = withContext(Dispatchers.IO) {
        val fileName = "wardrobe_${System.currentTimeMillis()}_${uri.lastPathSegment.hashCode()}.jpg"
        val target = File(imageDir, fileName)
        context.contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: error("Cannot open selected image")
        fileName
    }

    fun fileFor(fileName: String): File {
        return File(imageDir, fileName)
    }
}
