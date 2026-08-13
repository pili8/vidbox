package com.vidbox.vidbox

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
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
                    else -> result.notImplemented()
                }
            }
    }

    private fun listMediaFiles(dir: String): List<String> {
        val d = File(dir)
        if (!d.exists() || !d.isDirectory) return emptyList()
        return d.listFiles { f ->
            f.isFile && mediaExtensions.any { f.name.lowercase().endsWith(it) }
        }?.map { it.absolutePath }?.sorted() ?: emptyList()
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
}
