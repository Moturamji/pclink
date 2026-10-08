package com.example.pclink

import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "com.example.pclink/storage"
    private val SHARE_CHANNEL = "com.example.pclink/share_intent"

    private val bgExecutor = Executors.newSingleThreadExecutor()
    private val pendingSharedFiles = mutableListOf<String>()
    private var shareMethodChannel: MethodChannel? = null

    override fun getInitialRoute(): String {
        return "/"
    }

    override fun getRenderMode(): RenderMode {
        return RenderMode.texture
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        processShareIntentAsync(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        processShareIntentAsync(intent)
    }

    private fun processShareIntentAsync(incomingIntent: Intent?) {
        if (incomingIntent == null) return
        val action = incomingIntent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return
        }

        // Process in background executor so the UI and FlutterEngine startup are NEVER blocked
        bgExecutor.execute {
            val resolvedPaths = extractAndCacheSharedFiles(incomingIntent)
            if (resolvedPaths.isNotEmpty()) {
                synchronized(pendingSharedFiles) {
                    pendingSharedFiles.addAll(resolvedPaths)
                }
                runOnUiThread {
                    shareMethodChannel?.invokeMethod("onSharedFilesReceived", resolvedPaths)
                }
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Storage channel for downloads directory, media scanner, and folder opening
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPublicDownloadsDirectory" -> {
                    try {
                        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                        val pcLinkDir = File(downloadsDir, "PCLink")
                        if (!pcLinkDir.exists()) {
                            pcLinkDir.mkdirs()
                        }
                        result.success(pcLinkDir.absolutePath)
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.message, null)
                    }
                }
                "scanFile" -> {
                    val filePath = call.argument<String>("path")
                    if (filePath != null) {
                        val file = File(filePath)
                        if (file.exists()) {
                            MediaScannerConnection.scanFile(
                                this,
                                arrayOf(file.absolutePath),
                                null
                            ) { _, _ -> }
                            val mediaScanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
                            mediaScanIntent.data = Uri.fromFile(file)
                            sendBroadcast(mediaScanIntent)
                        }
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Path cannot be null", null)
                    }
                }
                "openFolder" -> {
                    val folderPath = call.argument<String>("path")
                    try {
                        val uri = Uri.parse(folderPath ?: Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath)
                        val intent = Intent(Intent.ACTION_VIEW)
                        intent.setDataAndType(uri, "resource/folder")
                        if (intent.resolveActivity(packageManager) != null) {
                            startActivity(intent)
                            result.success(true)
                        } else {
                            val altIntent = Intent(Intent.ACTION_GET_CONTENT)
                            altIntent.setDataAndType(uri, "*/*")
                            startActivity(altIntent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("OPEN_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Share intent channel for incoming files from system share sheet
        val shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        shareMethodChannel = shareChannel
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingSharedFiles" -> {
                    // Queue on the single-thread executor to guarantee any ongoing file extraction completes first
                    bgExecutor.execute {
                        val filesCopy: List<String>
                        synchronized(pendingSharedFiles) {
                            filesCopy = ArrayList(pendingSharedFiles)
                            pendingSharedFiles.clear()
                        }
                        runOnUiThread {
                            result.success(filesCopy)
                        }
                    }
                }
                "clearPendingSharedFiles" -> {
                    synchronized(pendingSharedFiles) {
                        pendingSharedFiles.clear()
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun extractAndCacheSharedFiles(intent: Intent): List<String> {
        val action = intent.action ?: return emptyList()
        val uris = mutableListOf<Uri>()

        // 1. Extract URIs from ClipData
        val clipData = intent.clipData
        if (clipData != null) {
            for (i in 0 until clipData.itemCount) {
                try {
                    val item = clipData.getItemAt(i)
                    val uri = item?.uri
                    if (uri != null) {
                        uris.add(uri)
                    }
                } catch (_: Exception) {}
            }
        }

        // 2. Extract URIs from EXTRA_STREAM fallback
        if (uris.isEmpty()) {
            try {
                if (action == Intent.ACTION_SEND) {
                    val streamUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    }
                    if (streamUri != null) {
                        uris.add(streamUri)
                    }
                } else if (action == Intent.ACTION_SEND_MULTIPLE) {
                    val streamUris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    }
                    if (streamUris != null) {
                        uris.addAll(streamUris)
                    }
                }
            } catch (_: Exception) {}
        }

        val cacheDir = File(cacheDir, "shared_incoming")
        if (!cacheDir.exists()) {
            cacheDir.mkdirs()
        }

        // Clean up temporary shared files older than 24 hours
        try {
            val oneDayAgo = System.currentTimeMillis() - 86400000L
            cacheDir.listFiles()?.forEach { oldFile ->
                if (oldFile.lastModified() < oneDayAgo) {
                    oldFile.delete()
                }
            }
        } catch (_: Exception) {}

        // 3. Handle plain text or link sharing if no URIs attached
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (uris.isEmpty() && !sharedText.isNullOrBlank()) {
            try {
                val textFile = File(cacheDir, "shared_text_${System.currentTimeMillis()}.txt")
                textFile.writeText(sharedText)
                return listOf(textFile.absolutePath)
            } catch (_: Exception) {}
        }

        val filePaths = mutableListOf<String>()

        for (uri in uris) {
            try {
                if (uri.scheme == "file") {
                    val path = uri.path
                    if (path != null && File(path).exists()) {
                        filePaths.add(path)
                        continue
                    }
                }

                // Resolve display name and mime type
                var originalName: String? = null
                try {
                    val cursor = contentResolver.query(uri, null, null, null, null)
                    cursor?.use {
                        if (it.moveToFirst()) {
                            val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameIndex != -1) {
                                originalName = it.getString(nameIndex)
                            }
                        }
                    }
                } catch (_: Exception) {}

                if (originalName.isNullOrBlank()) {
                    originalName = "shared_${System.currentTimeMillis()}"
                    val mimeType = try { contentResolver.getType(uri) } catch (_: Exception) { null }
                    if (mimeType != null) {
                        val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
                        if (!ext.isNullOrBlank()) {
                            originalName = "$originalName.$ext"
                        }
                    }
                }

                val safeName = originalName!!.replace("[\\\\/:*?\"<>|]".toRegex(), "_")
                val destFile = File(cacheDir, "${System.currentTimeMillis()}_$safeName")

                contentResolver.openInputStream(uri)?.use { input ->
                    destFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                if (destFile.exists() && destFile.length() > 0) {
                    filePaths.add(destFile.absolutePath)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        return filePaths
    }
}
