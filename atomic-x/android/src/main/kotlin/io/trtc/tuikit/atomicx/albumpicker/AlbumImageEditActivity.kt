package io.trtc.tuikit.atomicx.albumpicker

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.os.Build
import android.os.Bundle
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.exifinterface.media.ExifInterface
import io.trtc.tuikit.albumpickercore.api.ImageEditListener
import io.trtc.tuikit.albumpickercore.api.ImageEditView
import java.io.File
import java.io.IOException
import kotlin.concurrent.thread

/** 承载腾讯相册预览的原生编辑器，只导出独立副本。 */
internal class AlbumImageEditActivity : AppCompatActivity(), ImageEditListener {
    companion object {
        /** 应用内读取的原图路径。 */
        const val EXTRA_SOURCE = "imagePath"
        /** 本次编辑生成的缓存副本路径。 */
        const val EXTRA_OUTPUT = "editedPath"
        /** 编辑失败时返回给 Flutter 的提示。 */
        const val EXTRA_ERROR = "error"
    }

    private var editor: ImageEditView? = null
    // 写入完成前屏蔽重复确认和退出，避免留下半写入的副本。
    private var exporting = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.setBackgroundColor(android.graphics.Color.BLACK)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (!exporting && editor?.onBackPressed() != true) finish()
            }
        })
        val path = intent.getStringExtra(EXTRA_SOURCE)
        if (path == null) {
            finishWithError("无法读取图片")
            return
        }
        // 文件解码移出主线程，返回后再创建原生编辑界面。
        thread {
            val bitmap = runCatching { decode(File(path)) }.getOrNull()
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                if (bitmap == null) {
                    finishWithError("无法读取图片")
                } else {
                    val editView = ImageEditView(this, bitmap, this)
                    editor = editView
                    setContentView(editView)
                }
            }
        }
    }

    /** 按照片方向解码，兼容系统尚未提供 ImageDecoder 的版本。 */
    private fun decode(source: File): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return ImageDecoder.decodeBitmap(ImageDecoder.createSource(source)) { decoder, _, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        }
        val bitmap = BitmapFactory.decodeFile(source.path) ?: return null
        val exif = try {
            ExifInterface(source.path)
        } catch (_: IOException) {
            return bitmap
        }
        val rotation = exif.rotationDegrees
        if (!exif.isFlipped && rotation == 0) return bitmap
        val matrix = Matrix().apply {
            if (exif.isFlipped) postScale(-1f, 1f)
            postRotate(rotation.toFloat())
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    override fun onEditCompleted(editedBitmap: Bitmap) {
        if (exporting || isFinishing) return
        exporting = true
        thread {
            val output = runCatching { exportCopy(editedBitmap) }.getOrNull()
            runOnUiThread {
                if (isFinishing || isDestroyed) {
                    output?.delete()
                } else if (output == null) {
                    finishWithError("无法导出编辑图片")
                } else {
                    setResult(RESULT_OK, Intent().putExtra(EXTRA_OUTPUT, output.path))
                    finish()
                }
            }
        }
    }

    override fun onEditCancelled() {
        if (!exporting) finish()
    }

    /** 只写新建的缓存文件，导出失败时清理该文件。 */
    private fun exportCopy(bitmap: Bitmap): File {
        val output = File.createTempFile("album-edit-", ".png", cacheDir)
        try {
            output.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        } catch (error: Exception) {
            output.delete()
            throw error
        }
        return output
    }

    private fun finishWithError(message: String) {
        setResult(RESULT_FIRST_USER, Intent().putExtra(EXTRA_ERROR, message))
        finish()
    }
}
