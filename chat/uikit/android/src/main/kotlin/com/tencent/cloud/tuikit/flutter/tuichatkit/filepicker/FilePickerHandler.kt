package com.tencent.cloud.tuikit.flutter.tuichatkit.filepicker
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

/** 将文件选择和打开请求转交 Android 系统，并为外部应用授予临时读取权限。 */
class FilePickerHandler(
    private val context: Context,
    private val methodChannel: MethodChannel
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "FilePickerHandler"
        private const val FILE_PROVIDER_AUTH = ".BaseComponent.FileProvider"
    }

    private var pendingResult: MethodChannel.Result? = null

    init {
        setupFilePickerCallbacks()
    }

    private fun setupFilePickerCallbacks() {
        // Callbacks will be set when pickFiles is called
        //
        // 调用 pickFiles 时会设置回调。
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFiles" -> pickFiles(call, result)
            "openFile" -> openFile(call, result)
            else -> result.notImplemented()
        }
    }

    private fun pickFiles(call: MethodCall, result: MethodChannel.Result) {
        val maxCount = call.argument<Int>("maxCount") ?: 1
        val allowedMimeTypes = call.argument<List<String>>("allowedMimeTypes") ?: emptyList()

        pendingResult = result

        val config = FilePickerConfig(
            allowedMimeTypes = allowedMimeTypes,
            maxCount = maxCount
        )

        FilePicker.pickFiles(config, object : FilePickerListener {
            override fun onPicked(result: List<FilePickerResult>) {
                val resultData = result.map { file ->
                    mapOf(
                        "filePath" to file.filePath,
                        "fileName" to file.fileName,
                        "fileSize" to file.fileSize,
                        "extension" to file.extension
                    )
                }
                pendingResult?.success(resultData)
                pendingResult = null
            }

            override fun onCanceled() {
                pendingResult?.success(emptyList<Map<String, Any>>())
                pendingResult = null
            }
        })
    }

    /**
     * Open file with system default application
     * Reference: FileUtils.kt from android_compose
     *
     * 用系统默认应用打开文件，参考：android_compose 中的 FileUtils.kt
     */
    private fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath.isNullOrEmpty()) {
            Log.e(TAG, "openFile failed: file path is required")
            result.error("INVALID_ARGUMENTS", "File path is required", null)
            return
        }

        try {
            val file = File(filePath)
            
            // Check if file exists
            //
            // 检查文件是否存在
            if (!file.exists()) {
                Log.e(TAG, "openFile failed: file does not exist - $filePath")
                result.success(false)
                return
            }

            // Get URI from file path
            //
            // 从文件路径获取 URI
            val uri = getUriFromPath(filePath)
            if (uri == null) {
                Log.e(TAG, "openFile failed: uri is null")
                result.success(false)
                return
            }

            // 这里是本地路径，文件名中的 # 和 ? 都是普通字符。
            val fileExtension = file.extension.lowercase(Locale.ROOT)
            val mimeType = if (fileExtension.isNotEmpty()) {
                MimeTypeMap.getSingleton().getMimeTypeFromExtension(fileExtension)
            } else {
                null
            } ?: "*/*"

            Log.d(TAG, "Opening file: $filePath, extension: $fileExtension, MIME type: $mimeType")

            // Create intent
            //
            // 创建意图
            val intent = Intent(Intent.ACTION_VIEW).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                setDataAndType(uri, mimeType)
            }

            // Use chooser to let user select app
            //
            // 使用选择器让用户选择应用
            val chooserIntent = Intent.createChooser(intent, "Open file with")
            chooserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            
            context.startActivity(chooserIntent)
            Log.d(TAG, "File opened successfully")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "openFile failed: ${e.message}", e)
            result.success(false)
        }
    }

    /**
     * Get URI from file path
     * For Android N (API 24) and above, use FileProvider
     * For older versions, use Uri.fromFile
     *
     * 从文件路径获取 URI
     */
    private fun getUriFromPath(path: String): Uri? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(
                    context,
                    context.applicationInfo.packageName + FILE_PROVIDER_AUTH,
                    File(path)
                )
            } else {
                Uri.fromFile(File(path))
            }
        } catch (e: Exception) {
            Log.e(TAG, "getUriFromPath failed: ${e.message}", e)
            null
        }
    }

    fun dispose() {
        pendingResult = null
    }
}
