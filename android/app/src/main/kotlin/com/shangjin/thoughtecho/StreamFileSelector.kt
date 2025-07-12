package com.shangjin.thoughtecho

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

class StreamFileSelector: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingResult: Result? = null
    
    companion object {
        private const val REQUEST_CODE_SELECT_FILE = 1001
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "thoughtecho/file_selector")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "selectVideoFile" -> {
                selectFile(result, arrayOf("video/*"))
            }
            "selectImageFile" -> {
                selectFile(result, arrayOf("image/*"))
            }
            "selectFile" -> {
                val extensions = call.argument<List<String>>("extensions") ?: emptyList()
                val mimeTypes = convertExtensionsToMimeTypes(extensions)
                selectFile(result, mimeTypes.toTypedArray())
            }
            "isAvailable" -> {
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun selectFile(result: Result, mimeTypes: Array<String>) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        if (pendingResult != null) {
            result.error("ALREADY_ACTIVE", "File selection already in progress", null)
            return
        }

        pendingResult = result

        try {
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                type = if (mimeTypes.size == 1) mimeTypes[0] else "*/*"
                if (mimeTypes.size > 1) {
                    putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes)
                }
                addCategory(Intent.CATEGORY_OPENABLE)
                // 关键：不要预加载文件内容，只获取URI
                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            }

            activity?.startActivityForResult(
                Intent.createChooser(intent, "选择文件"),
                REQUEST_CODE_SELECT_FILE
            )
        } catch (e: Exception) {
            pendingResult = null
            result.error("SELECTION_ERROR", "Failed to start file selection: ${e.message}", null)
        }
    }

    private fun convertExtensionsToMimeTypes(extensions: List<String>): List<String> {
        val mimeTypeMap = mapOf(
            "mp4" to "video/mp4",
            "mov" to "video/quicktime",
            "avi" to "video/x-msvideo",
            "mkv" to "video/x-matroska",
            "webm" to "video/webm",
            "3gp" to "video/3gpp",
            "m4v" to "video/x-m4v",
            "jpg" to "image/jpeg",
            "jpeg" to "image/jpeg",
            "png" to "image/png",
            "gif" to "image/gif",
            "bmp" to "image/bmp",
            "webp" to "image/webp",
            "zip" to "application/zip",
            "json" to "application/json"
        )

        return extensions.mapNotNull { ext ->
            mimeTypeMap[ext.lowercase()]
        }.ifEmpty { listOf("*/*") }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_CODE_SELECT_FILE) {
            val result = pendingResult
            pendingResult = null

            if (result == null) {
                return true
            }

            if (resultCode == Activity.RESULT_OK && data != null) {
                val uri: Uri? = data.data
                if (uri != null) {
                    try {
                        // 关键：只返回文件路径，不读取文件内容
                        val filePath = getFilePathFromUri(uri)
                        if (filePath != null) {
                            result.success(filePath)
                        } else {
                            result.error("PATH_ERROR", "Could not get file path from URI", null)
                        }
                    } catch (e: Exception) {
                        result.error("PATH_ERROR", "Error getting file path: ${e.message}", null)
                    }
                } else {
                    result.error("NO_FILE", "No file selected", null)
                }
            } else {
                result.success(null) // 用户取消选择
            }
            return true
        }
        return false
    }

    private fun getFilePathFromUri(uri: Uri): String? {
        return try {
            // 对于content:// URI，我们需要复制到临时位置
            // 但这里我们直接返回URI字符串，让Dart层处理
            // 这样避免在原生层读取大文件内容
            when (uri.scheme) {
                "file" -> uri.path
                "content" -> {
                    // 返回content URI，让Dart层通过流式方式处理
                    uri.toString()
                }
                else -> uri.toString()
            }
        } catch (e: Exception) {
            null
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}