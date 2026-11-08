package io.trtc.tuikit.atomicx.albumpicker

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.trtc.tuikit.atomicx.albumpicker.*
import io.trtc.tuikit.atomicx.basecomponent.utils.ContextProvider
import io.trtc.tuikit.atomicx.utils.FileUtils
import io.trtc.tuikit.albumpickercore.api.CompressQuality
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/// 桥接 Flutter 与原生相册选择器，确认选择先通知占位，耗时媒体处理通过独立事件回传。
class AlbumPickerHandler(
    private val flutterAssets: FlutterPlugin.FlutterAssets?,
    private val eventSink: (Map<String, Any>) -> Unit
) {

    companion object {
        private const val TAG = "AlbumPickerHandler"

        internal var pendingConfig: AlbumPickerConfig? = null
        internal var pendingTheme: AlbumPickerTheme? = null
        internal var pendingListener: AlbumPickerListener? = null

        internal fun cleanup() {
            pendingConfig = null
            pendingTheme = null
            pendingListener = null
        }
    }

    private var pendingResult: MethodChannel.Result? = null
    private var sessionId: String? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun handlePickMedia(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "handlePickMedia called")
        completePreviousSessionIfNeeded()

        try {
            pendingResult = result
            sessionId = call.argument<String>("sessionId")

            val config = buildConfig(call)
            val theme = buildTheme(call)

            Log.d(TAG, "Config - style: ${config.style}, mediaFilter: ${config.mediaFilter}, " +
                    "maxCount: ${config.maxSelectionCount}, gridCount: ${config.itemsPerRow}")

            Companion.pendingConfig = config
            Companion.pendingTheme = theme
            Companion.pendingListener =
                createAlbumPickerListener(call.argument<Boolean>("includeSourceMetadata") == true)

            launchHostActivity()
        } catch (e: Exception) {
            Log.e(TAG, "Error in handlePickMedia", e)
            completeWithError("ALBUM_PICKER_ERROR", e.message)
        }
    }

    private fun buildConfig(call: MethodCall): AlbumPickerConfig {
        val config = AlbumPickerConfig()

        call.argument<Int>("pickMode")?.let {
            config.mediaFilter = when (it) {
                0 -> AlbumPickerMediaFilter.IMAGE_ONLY
                1 -> AlbumPickerMediaFilter.VIDEO_ONLY
                else -> AlbumPickerMediaFilter.ALL
            }
        }
        call.argument<Int>("style")?.let {
            config.style = if (it == 1) AlbumPickerStyle.LIKE_WHATSAPP else AlbumPickerStyle.LIKE_WECHAT
        }
        call.argument<Int>("maxCount")?.let { config.maxSelectionCount = it }
        call.argument<Int>("gridCount")?.let { config.itemsPerRow = it }
        call.argument<Boolean>("showsCameraItem")?.let { config.showsCameraItem = it }
        call.argument<Int>("language")?.let {
            config.language = when (it) {
                0 -> AlbumPickerLanguage.SYSTEM
                1 -> AlbumPickerLanguage.EN
                2 -> AlbumPickerLanguage.ZH_HANS
                3 -> AlbumPickerLanguage.ZH_HANT
                4 -> AlbumPickerLanguage.AR
                else -> AlbumPickerLanguage.SYSTEM
            }
        }
        call.argument<Int>("compressQuality")?.let {
            config.compressQuality = if (it == 1) CompressQuality.HIGH else CompressQuality.STANDARD
        }
        call.argument<Int>("maxVideoDurationInSeconds")?.let {
            config.maxVideoDurationInSeconds = it
        }
        call.argument<Int>("maxOutputFileSizeInMB")?.let {
            config.maxOutputFileSizeInMB = it
        }

        return config
    }

    private fun buildTheme(call: MethodCall): AlbumPickerTheme {
        return AlbumPickerTheme(
            currentPrimaryColor = parseColor(call.argument("primaryColor")),
            backgroundColor = parseColor(call.argument("backgroundColor")),
            backgroundColorSecondary = parseColor(call.argument("backgroundColorSecondary")),
            textColor = parseColor(call.argument("textColor")),
            textColorSecondary = parseColor(call.argument("textColorSecondary")),
            confirmButtonIcon = loadFlutterAssetDrawable(call.argument("confirmButtonIconAsset")),
            bigFontSize = call.argument<Double>("bigFontSize")?.toFloat(),
            normalFontSize = call.argument<Double>("normalFontSize")?.toFloat(),
            smallFontSize = call.argument<Double>("smallFontSize")?.toFloat(),
            bigRadius = call.argument<Double>("bigRadius")?.toInt(),
            normalRadius = call.argument<Double>("normalRadius")?.toInt(),
            smallRadius = call.argument<Double>("smallRadius")?.toInt(),
        )
    }

    private fun completePreviousSessionIfNeeded() {
        if (pendingResult == null) return
        Log.d(TAG, "Completing previous pending result before starting new session")
        pendingResult?.success(null)
        pendingResult = null
        Companion.cleanup()
    }

    private fun completeSession() {
        mainHandler.post {
            pendingResult?.success(null)
            pendingResult = null
        }
    }

    private fun completeWithError(code: String, message: String?) {
        mainHandler.post {
            pendingResult?.error(code, message, null)
            pendingResult = null
            Companion.cleanup()
        }
    }

    private fun launchHostActivity() {
        val context = ContextProvider.appContext
        val intent = Intent(context, AlbumPickerHostActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    /// 确认事件先回传原件资料，再处理缩略图，导出进度与确认共用同一队列。
    private fun createAlbumPickerListener(includeSourceMetadata: Boolean): AlbumPickerListener {
        val capturedSessionId = sessionId

        return object : AlbumPickerListener {
            override fun onPickConfirm(pickedAlbumMedias: List<AlbumMedia>, textMessage: String?) {
                Log.d(TAG, "onPickConfirm: ${pickedAlbumMedias.size} items selected")

                val host = AlbumPickerHostActivity.currentInstance
                // 关闭界面前读取此次确认的选项，后台导出期间不再访问视图。
                val original = includeSourceMetadata && host?.isSendingOriginal() == true
                host?.finish()

                executor.execute {
                    val event = mutableMapOf<String, Any>(
                        "type" to "onPickConfirm",
                        "pickedAlbumMedias" to pickedAlbumMedias.map { media ->
                            val data = buildMediaDataMap(media)
                            if (original) data + sourceMetadata(media.uri) + ("isOriginal" to true)
                            else data
                        },
                    )
                    textMessage?.let { event["textMessage"] = it }
                    capturedSessionId?.let { event["sessionId"] = it }
                    mainHandler.post { eventSink(event) }

                    // 先让聊天显示正确的占位，封面继续使用原有后台准备流程。
                    for (media in pickedAlbumMedias) {
                        if (media.videoThumbnailPath == null) {
                            media.videoThumbnailPath = generateThumbnailForMedia(media)
                        }
                    }
                }

                if (pickedAlbumMedias.isEmpty()) {
                    completeSession()
                }
            }

            override fun onMediaProcessing(albumMedia: AlbumMedia, progress: Float, error: Boolean) {
                if (progress >= 1.0f && !error && albumMedia.mediaPath.isNullOrEmpty()) {
                    Log.d(TAG, "onMediaProcessing: skipping callback with empty path at progress=1.0")
                    return
                }

                executor.execute {
                    try {
                        val event = mutableMapOf<String, Any>(
                            "type" to "onMediaProcessing",
                            "data" to buildMediaDataMap(albumMedia),
                            "progress" to progress.toDouble(),
                            "error" to error,
                        )
                        capturedSessionId?.let { event["sessionId"] = it }
                        mainHandler.post { eventSink(event) }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in onMediaProcessing", e)
                    }
                }
            }

            override fun onMediaProcessed() {
                Log.d(TAG, "onMediaProcessed")
                executor.execute {
                    val event = mutableMapOf<String, Any>("type" to "onMediaProcessed")
                    capturedSessionId?.let { event["sessionId"] = it }
                    mainHandler.post { eventSink(event) }
                    mainHandler.post { completeSession() }
                }
            }

            override fun onCancel() {
                Log.d(TAG, "onCancel")
                val event = mutableMapOf<String, Any>("type" to "onCancel")
                capturedSessionId?.let { event["sessionId"] = it }
                mainHandler.post { eventSink(event) }
                AlbumPickerHostActivity.currentInstance?.finish()
                completeSession()
            }
        }
    }

    /// 原件大小以内容提供者元数据为准，未知时留给导出结果判定。
    private fun sourceMetadata(uri: Uri?): Map<String, Any> {
        if (uri == null) return emptyMap()
        val resolver = ContextProvider.appContext.contentResolver
        val fields = mutableMapOf<String, Any>()
        runCatching {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
                ?.use { cursor ->
                    if (!cursor.moveToFirst()) return@use
                    val name = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val size = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (name >= 0 && !cursor.isNull(name)) fields["sourceFileName"] = cursor.getString(name)
                    if (size >= 0 && !cursor.isNull(size)) fields["sourceFileSize"] = cursor.getLong(size)
                }
        }
        if (fields["sourceFileSize"] == null && uri.scheme == "file") {
            uri.path?.let { File(it) }?.takeIf { it.isFile }?.let {
                fields["sourceFileName"] = it.name
                fields["sourceFileSize"] = it.length()
            }
        }
        return fields
    }

    // MARK: - Thumbnail Generation

    private fun generateThumbnailForMedia(albumMedia: AlbumMedia): String? {
        val context = ContextProvider.appContext
        val id = albumMedia.id.toLong()

        val uri = if (!albumMedia.mediaPath.isNullOrEmpty()) {
            Uri.fromFile(File(albumMedia.mediaPath!!))
        } else {
            albumMedia.uri
        } ?: return null

        return try {
            when (albumMedia.mediaType) {
                AlbumMediaType.VIDEO -> generateVideoThumbnail(context, uri, id)
                AlbumMediaType.IMAGE -> generateImageThumbnail(context, uri, id)
                else -> null
            }
        } catch (e: Exception) {
            Log.e(TAG, "generateThumbnailForMedia failed", e)
            null
        }
    }

    private fun generateImageThumbnail(context: android.content.Context, uri: Uri, id: Long): String? {
        val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, boundsOptions)
        }

        val maxEdge = maxOf(boundsOptions.outWidth, boundsOptions.outHeight)
        val sampleSize = if (maxEdge > 0) maxOf(1, maxEdge / 540) else 1

        val decodeOptions = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val bitmap = context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, decodeOptions)
        } ?: return null

        return saveThumbnailToCache(context, bitmap, id)
    }

    private fun generateVideoThumbnail(context: android.content.Context, uri: Uri, id: Long): String? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            val bitmap = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return null
            saveThumbnailToCache(context, bitmap, id)
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    private fun saveThumbnailToCache(context: android.content.Context, bitmap: Bitmap, id: Long): String? {
        val cacheDir = File(context.cacheDir, "album_picker_thumbnails").apply { mkdirs() }
        val file = File(cacheDir, "${id}_${System.currentTimeMillis()}_thumb.jpg")
        return try {
            FileOutputStream(file).use { fos ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, fos)
            }
            bitmap.recycle()
            file.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "saveThumbnailToCache failed", e)
            null
        }
    }

    private fun buildMediaDataMap(albumMedia: AlbumMedia): Map<String, Any> {
        val mediaPath = albumMedia.mediaPath ?: ""
        val mediaTypeInt = if (albumMedia.mediaType == AlbumMediaType.VIDEO) 1 else 0

        val dataMap = mutableMapOf<String, Any>(
            "id" to albumMedia.id.toLong(),
            "uri" to (albumMedia.uri?.toString() ?: ""),
            "mediaType" to mediaTypeInt,
            "mediaPath" to mediaPath,
            "fileExtension" to if (mediaPath.isEmpty()) "" else FileUtils.getFileExtensionFromUrl(mediaPath),
            "fileSize" to if (mediaPath.isEmpty()) 0L else FileUtils.getFileSize(mediaPath),
            "duration" to albumMedia.duration.toLong(),
        )
        albumMedia.videoThumbnailPath?.let { dataMap["videoThumbnailPath"] = it }
        return dataMap
    }

    private fun parseColor(colorStr: String?): Int? {
        if (colorStr.isNullOrEmpty()) return null
        return try {
            colorStr.removePrefix("0x").removePrefix("0X").removePrefix("#")
                .toLong(16).toInt()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse color: $colorStr", e)
            null
        }
    }

    private fun loadFlutterAssetDrawable(assetPath: String?): Drawable? {
        if (assetPath.isNullOrEmpty() || flutterAssets == null) return null
        return try {
            val resolvedPath = flutterAssets.getAssetFilePathByName(assetPath)
            val context = ContextProvider.appContext
            context.assets.open(resolvedPath).use { inputStream ->
                BitmapFactory.decodeStream(inputStream)?.let {
                    BitmapDrawable(context.resources, it)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load Flutter asset: $assetPath", e)
            null
        }
    }
}
