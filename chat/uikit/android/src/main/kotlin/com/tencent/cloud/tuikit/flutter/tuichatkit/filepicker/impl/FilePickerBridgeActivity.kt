package com.tencent.cloud.tuikit.flutter.tuichatkit.filepicker.impl
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import com.tencent.cloud.tuikit.flutter.tuichatkit.filepicker.FilePickerResult
import com.tencent.cloud.tuikit.flutter.tuichatkit.filepicker.util.FilePickerUtils

class FilePickerBridgeActivity : ComponentActivity() {

    companion object {
        private const val TAG = "FilePickerBridgeAct"
    }

    private lateinit var filePickerLauncher: ActivityResultLauncher<Intent>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Set transparent theme
        //
        // 设置透明主题
        setTheme(android.R.style.Theme_Translucent_NoTitleBar)

        // Check if config and listener are available
        //
        // 检查配置和监听器是否可用
        if (SystemFilePicker.filePickerConfig == null || SystemFilePicker.filePickerListener == null) {
            finish()
            return
        }

        // Register activity result launcher
        //
        // 注册活动结果启动器
        filePickerLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == RESULT_OK && result.data != null) {
                val selectedFiles = mutableListOf<FilePickerResult>()

                // Handle multiple files
                //
                // 处理多个文件
                val clipData: ClipData? = result.data?.clipData
                if (clipData != null) {
                    val maxSelection = SystemFilePicker.filePickerConfig?.maxCount ?: Int.MAX_VALUE
                    val itemCount = clipData.itemCount.coerceAtMost(maxSelection)

                    for (i in 0 until itemCount) {
                        val uri = clipData.getItemAt(i).uri
                        processUri(uri)?.let { selectedFiles.add(it) }
                    }
                } else {
                    // Handle single file
                    //
                    // 处理单个文件
                    val uri = result.data?.data
                    if (uri != null) {
                        processUri(uri)?.let { selectedFiles.add(it) }
                    }
                }

                // Callback with results
                //
                // 结果回调
                if (selectedFiles.isNotEmpty()) {
                    SystemFilePicker.filePickerListener?.onPicked(selectedFiles)
                } else {
                    SystemFilePicker.filePickerListener?.onCanceled()
                }
            } else {
                // User canceled
                //
                // 用户已取消
                SystemFilePicker.filePickerListener?.onCanceled()
            }

            // Clean up
            //
            // 清理
            SystemFilePicker.filePickerListener = null
            SystemFilePicker.filePickerConfig = null

            // Finish activity
            //
            // 结束活动
            finish()
        }

        // Launch file picker
        //
        // 启动文件选择器
        launchFilePicker()
    }

    private fun launchFilePicker() {
        val config = SystemFilePicker.filePickerConfig!!

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            // Set MIME type
            //
            // 设置 MIME 类型
            if (config.allowedMimeTypes.isNotEmpty()) {
                type = config.allowedMimeTypes.first()
                if (config.allowedMimeTypes.size > 1) {
                    putExtra(Intent.EXTRA_MIME_TYPES, config.allowedMimeTypes.toTypedArray())
                }
            } else {
                type = "*/*"
            }

            addCategory(Intent.CATEGORY_OPENABLE)

            // Allow multiple selection
            //
            // 允许多选
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, config.maxCount > 1)

            // Grant read permission
            //
            // 授予读取权限
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        try {
            filePickerLauncher.launch(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start file picker", e)
            SystemFilePicker.filePickerListener?.onCanceled()
            SystemFilePicker.filePickerListener = null
            SystemFilePicker.filePickerConfig = null
            finish()
        }
    }

    private fun processUri(uri: Uri): FilePickerResult? {
        if (!isValidFile(uri)) {
            return null
        }

        // Copy file to app directory
        //
        // 复制文件到应用目录
        val copiedFile = FilePickerUtils.copyFileToAppDir(this, uri)
        if (copiedFile == null) {
            Log.e(TAG, "Failed to copy file")
            return null
        }

        val fileName = FilePickerUtils.getFileName(this, uri) ?: copiedFile.name
        val fileSize = copiedFile.length()
        val extension = copiedFile.extension.lowercase()

        return FilePickerResult(
            filePath = copiedFile.absolutePath,
            fileName = fileName,
            fileSize = fileSize,
            extension = extension
        )
    }

    private fun isValidFile(uri: Uri): Boolean {
        try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val displayNameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (displayNameIndex != -1) {
                        return true
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error validating file URI", e)
        }
        return false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onBackPressed() {
        super.onBackPressed()

        SystemFilePicker.filePickerListener?.onCanceled()
        SystemFilePicker.filePickerListener = null
        SystemFilePicker.filePickerConfig = null
    }
}
