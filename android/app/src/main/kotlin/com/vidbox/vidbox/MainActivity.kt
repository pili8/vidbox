package com.vidbox.vidbox

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import java.io.ByteArrayOutputStream
import java.io.File

/// VidBox 原生文件操作通道。
///
/// 个人侧载应用申请 MANAGE_EXTERNAL_STORAGE 后，直接用 java.io.File 操作，
/// 无需 MediaStore 抽象。所有方法都在主线程的轻量文件元数据操作，
/// 大量文件扫描的耗时问题后续再优化。
class MainActivity : FlutterActivity() {
    private val channelName = "vidbox/file"

    private val mediaExtensions = setOf(
        ".mp4", ".webp", ".jpg", ".jpeg", ".png", ".gif",
        ".mov", ".mkv", ".avi", ".3gp",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listMediaFiles" -> {
                        val dir = call.argument<String>("dir") ?: ""
                        result.success(listMediaFiles(dir))
                    }
                    "listMediaFilesMeta" -> {
                        val dir = call.argument<String>("dir") ?: ""
                        result.success(listMediaFilesMeta(dir))
                    }
                    "renameFile" -> {
                        val src = call.argument<String>("src") ?: ""
                        val newName = call.argument<String>("newName") ?: ""
                        result.success(renameFile(src, newName))
                    }
                    "moveFile" -> {
                        val src = call.argument<String>("src") ?: ""
                        val dstDir = call.argument<String>("dstDir") ?: ""
                        result.success(moveFile(src, dstDir))
                    }
                    "deleteToTrash" -> {
                        val src = call.argument<String>("src") ?: ""
                        result.success(deleteToTrash(src))
                    }
                    "getThumbnail" -> {
                        val path = call.argument<String>("path") ?: ""
                        result.success(getThumbnail(path))
                    }
                    "listTrash" -> {
                        val dir = call.argument<String>("dir") ?: ""
                        result.success(listTrash(dir))
                    }
                    "restoreFromTrash" -> {
                        val src = call.argument<String>("src") ?: ""
                        result.success(restoreFromTrash(src))
                    }
                    "emptyTrash" -> {
                        val dir = call.argument<String>("dir") ?: ""
                        result.success(emptyTrash(dir))
                    }
                    "listSubDirs" -> {
                        val dir = call.argument<String>("dir") ?: ""
                        result.success(listSubDirs(dir))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // 返回每个媒体文件的 {path, mtime, size}，供 Dart 侧做增量索引。
    private fun listMediaFilesMeta(dir: String): List<Map<String, Any>> {
        val d = File(dir)
        if (!d.exists() || !d.isDirectory) return emptyList()
        val result = mutableListOf<Map<String, Any>>()
        fun walk(f: File) {
            val children = f.listFiles() ?: return
            for (c in children) {
                when {
                    c.isDirectory && !c.name.startsWith(".") -> walk(c)
                    c.isFile && mediaExtensions.any { c.name.lowercase().endsWith(it) } ->
                        result.add(
                            mapOf(
                                "path" to c.absolutePath,
                                "mtime" to c.lastModified(),
                                "size" to c.length(),
                            )
                        )
                }
            }
        }
        walk(d)
        return result
    }

    private fun listMediaFiles(dir: String): List<String> {
        val d = File(dir)
        if (!d.exists() || !d.isDirectory) return emptyList()
        val result = mutableListOf<String>()
        fun walk(f: File) {
            val children = f.listFiles() ?: return
            for (c in children) {
                when {
                    // 跳过隐藏目录（.trash 等）
                    c.isDirectory && !c.name.startsWith(".") -> walk(c)
                    c.isFile && mediaExtensions.any { c.name.lowercase().endsWith(it) } ->
                        result.add(c.absolutePath)
                }
            }
        }
        walk(d)
        return result.sorted()
    }

    private fun renameFile(src: String, newName: String): String? {
        val f = File(src)
        if (!f.exists()) return null
        val parent = f.parentFile ?: return null
        val dest = File(parent, newName)
        return if (f.renameTo(dest)) dest.absolutePath else null
    }

    private fun moveFile(src: String, dstDir: String): Boolean {
        val f = File(src)
        if (!f.exists()) return false
        val destDir = File(dstDir)
        if (!destDir.exists()) destDir.mkdirs()
        val dest = File(destDir, f.name)
        return if (dest.exists()) false else f.renameTo(dest)
    }

    private fun deleteToTrash(src: String): Boolean {
        val f = File(src)
        if (!f.exists()) return false
        val parent = f.parentFile ?: return false
        val trashDir = File(parent, ".trash")
        if (!trashDir.exists()) trashDir.mkdirs()
        val dest = File(trashDir, f.name)
        return if (dest.exists()) false else f.renameTo(dest)
    }

    private fun getThumbnail(path: String): ByteArray? {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(path)
            val bitmap = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            retriever.release()
            if (bitmap == null) {
                null
            } else {
                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)
                stream.toByteArray()
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun listTrash(dir: String): List<String> {
        val trashDir = File(dir, ".trash")
        if (!trashDir.exists() || !trashDir.isDirectory) return emptyList()
        return trashDir.listFiles { f -> f.isFile }
            ?.map { it.absolutePath }?.sorted() ?: emptyList()
    }

    private fun restoreFromTrash(src: String): Boolean {
        val f = File(src)
        if (!f.exists()) return false
        val trashParent = f.parentFile ?: return false
        val originalDir = trashParent.parentFile ?: return false
        val dest = File(originalDir, f.name)
        return if (dest.exists()) false else f.renameTo(dest)
    }

    private fun emptyTrash(dir: String): Boolean {
        val trashDir = File(dir, ".trash")
        if (!trashDir.exists()) return true
        return trashDir.listFiles()?.all { it.delete() } ?: false
    }

    private fun listSubDirs(dir: String): List<String> {
        val d = File(dir)
        if (!d.exists() || !d.isDirectory) return emptyList()
        return d.listFiles { f -> f.isDirectory && !f.name.startsWith(".") }
            ?.map { it.name }?.sorted() ?: emptyList()
    }
}
