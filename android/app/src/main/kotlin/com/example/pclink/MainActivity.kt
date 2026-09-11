package com.example.pclink

import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.pclink/storage"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
                                context,
                                arrayOf(file.absolutePath),
                                null
                            ) { path, uri ->
                                // Scanned successfully
                            }
                            // Also send broadcast for older devices
                            val mediaScanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
                            mediaScanIntent.data = Uri.fromFile(file)
                            context.sendBroadcast(mediaScanIntent)
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
    }
}
