package com.vidbox.vidbox

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/// VidBox 原生文件操作通道。
///
/// 个人侧载应用申请 MANAGE_EXTERNAL_STORAGE 后，直接用 java.io.File 操作。
/// 耗时操作（扫描、缩略图、回收站遍历）在后台线程执行，结果回主线程，
/// 避免千级文件时主线程阻塞/ANR。
class MainActivity : FlutterActivity() {
    private val channelName = "vidbox/file"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newFixedThreadPool(4)

    private val mediaExtensions = setOf(
        ".mp4", ".webp", ".jpg", ".jpeg", ".png", ".gif",
        ".mov", ".mkv", ".avi", ".3gp",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 重操作：后台线程执行
                    "listMediaFiles" -> runAsync(result) {
                        listMediaFiles(call.argument<String>("dir") ?: "")
                    }
                    "listMediaFilesMeta" -> runAsync(result) {
                        listMediaFilesMeta(call.argument<String>("dir") ?: "")
                    }
                    "getThumbnail" -> runAsync(result) {
                        getThumbnail(call.argument<String>("path") ?: "")
                    }
                    "listTrash" -> runAsync(result) {
                        listTrash(call.argument<String>("dir") ?: "")
                    }
                    "cleanupTrash" -> runAsync(result) {
                        cleanupTrash(
                            call.argument<String>("dir") ?: "",
                            call.argument<Int>("days") ?: 30,
                        )
                    }
                    "emptyTrash" -> runAsync(result) {
                        emptyTrash(call.argument<String>("dir") ?: "")
                    }
                    "listSubDirs" -> runAsync(result) {
                        listSubDirs(call.argument<String>("dir") ?: "")
                    }
                    // 轻操作：主线程直接执行
                    "renameFile" -> result.success(
                        renameFile(
                            call.argument<String>("src") ?: "",
                            call.argument<String>("newName") ?: "",
                        )
                    )
                    "moveFile" -> result.success(
                        moveFile(
                            call.argument<String>("src") ?: "",
                            call.argument<String>("dstDir") ?: "",
                        )
                    )
                    "deleteToTrash" -> result.success(
                        deleteToTrash(call.argument<String>("src") ?: "")
                    )
                    "restoreFromTrash" -> result.success(
                        restoreFromTrash(call.argument<String>("src") ?: "")
                    )
                    else -> result.notImplemented()
                }
            }
    }

    /// 在后台线程执行 [block]，完成后回到主线程用 [result] 返回。
    private fun <T> runAsync(result: MethodChannel.Result, block: () -> T) {
        executor.execute {
            val value = try {
                block()
            } catch (e: Exception) {
                null
            }
            mainHandler.post { result.success(value) }
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

    /// 清理 .trash 中超过 [days] 天的文件，返回删除的文件数。
    private fun cleanupTrash(dir: String, days: Int): Int {
        val trashDir = File(dir, ".trash")
        if (!trashDir.exists() || !trashDir.isDirectory) return 0
        val cutoff = System.currentTimeMillis() - days * 24L * 3600L * 1000L
        val files = trashDir.listFiles { f -> f.isFile } ?: return 0
        var removed = 0
        for (f in files) {
            if (f.lastModified() < cutoff && f.delete()) removed++
        }
        return removed
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
