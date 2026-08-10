package com.swiftoilfield.swift_shipping_label

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.swiftoilfield.swift_shipping_label/native"
    private var pendingResult: MethodChannel.Result? = null
    private val pickImages = 1001
    private val pickPdf = 1002

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareFile" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mime") ?: "application/pdf"
                        val subject =
                            call.argument<String>("subject") ?: "Swift Supply Shipping Label"
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "Missing path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            shareFile(path, mime, subject)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("share_failed", e.message, null)
                        }
                    }
                    "pickImages" -> {
                        if (pendingResult != null) {
                            result.error("busy", "Picker already open", null)
                            return@setMethodCallHandler
                        }
                        val multiple = call.argument<Boolean>("multiple") ?: false
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "image/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
                        }
                        startActivityForResult(
                            Intent.createChooser(intent, "Select logo(s)"),
                            pickImages,
                        )
                    }
                    "pickPdf" -> {
                        if (pendingResult != null) {
                            result.error("busy", "Picker already open", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "application/pdf"
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        startActivityForResult(
                            Intent.createChooser(intent, "Select Order Acknowledgement PDF"),
                            pickPdf,
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun shareFile(path: String, mime: String, subject: String) {
        val file = File(path)
        if (!file.exists() || file.length() == 0L) {
            throw IllegalArgumentException("File missing or empty")
        }
        val shareTarget = fileForProvider(file)
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            shareTarget,
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, subject)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, subject))
    }

    /**
     * FileProvider only exposes cache, files, and external-files — not Flutter's
     * app_flutter documents tree. Copy into cache/share when needed.
     */
    private fun fileForProvider(source: File): File {
        val canonical = source.canonicalFile
        val allowedRoots = listOfNotNull(cacheDir, filesDir, getExternalFilesDir(null))
        for (root in allowedRoots) {
            val rootPath = root.canonicalFile.path
            val filePath = canonical.path
            if (filePath == rootPath || filePath.startsWith("$rootPath/")) {
                return canonical
            }
        }
        val shareDir = File(cacheDir, "share").apply { mkdirs() }
        var dest = File(shareDir, canonical.name.ifBlank { "document.pdf" })
        if (dest.exists()) {
            val stem = dest.nameWithoutExtension.ifBlank { "document" }
            val ext = dest.extension.ifEmpty { "pdf" }
            var n = 2
            while (dest.exists()) {
                dest = File(shareDir, "$stem ($n).$ext")
                n++
            }
        }
        canonical.copyTo(dest, overwrite = true)
        return dest
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickImages && requestCode != pickPdf) return
        val result = pendingResult
        pendingResult = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            if (requestCode == pickPdf) {
                result.success(null)
            } else {
                result.success(emptyList<String>())
            }
            return
        }
        try {
            if (requestCode == pickPdf) {
                val path = data.data?.let { uri -> copyUriToCache(uri, "picked_docs") }
                result.success(path)
                return
            }
            val paths = mutableListOf<String>()
            val clip = data.clipData
            if (clip != null) {
                for (i in 0 until clip.itemCount) {
                    clip.getItemAt(i).uri?.let { uri ->
                        copyUriToCache(uri)?.let { paths.add(it) }
                    }
                }
            } else {
                data.data?.let { uri ->
                    copyUriToCache(uri)?.let { paths.add(it) }
                }
            }
            result.success(paths)
        } catch (e: Exception) {
            result.error("pick_failed", e.message, null)
        }
    }

    private fun copyUriToCache(
        uri: Uri,
        subdir: String = "picked_logos",
    ): String? {
        val name = contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (cursor.moveToFirst() && idx >= 0) cursor.getString(idx) else null
        } ?: if (subdir == "picked_docs") {
            "order_ack_${System.currentTimeMillis()}.pdf"
        } else {
            "logo_${System.currentTimeMillis()}.png"
        }

        val destDir = File(cacheDir, subdir).apply { mkdirs() }
        var dest = File(destDir, name)
        if (dest.exists()) {
            val stem = dest.nameWithoutExtension
            val ext = dest.extension.ifEmpty {
                if (subdir == "picked_docs") "pdf" else "png"
            }
            var n = 2
            while (dest.exists()) {
                dest = File(destDir, "$stem ($n).$ext")
                n++
            }
        }
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(dest).use { output -> input.copyTo(output) }
        } ?: return null
        return dest.absolutePath
    }
}
