package io.trtc.tuikit.atomicx.albumpicker

import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import io.trtc.tuikit.albumpickercore.api.AlbumPickerStore

/// 承载腾讯相册界面，确认时提供当前会话的原文件选择状态。
class AlbumPickerHostActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "AlbumPickerHostActivity"
        var currentInstance: AlbumPickerHostActivity? = null
    }

    private var pickerView: AlbumPickerView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentInstance = this

        val config = AlbumPickerHandler.pendingConfig
        val theme = AlbumPickerHandler.pendingTheme ?: AlbumPickerTheme()
        val listener = AlbumPickerHandler.pendingListener

        if (config == null || listener == null) {
            Log.e(TAG, "Missing config or listener, finishing activity")
            finish()
            return
        }

        pickerView = AlbumPickerView(this)
        setContentView(pickerView)

        pickerView?.initialize(config = config, theme = theme, listener = listener)
    }

    /// 腾讯当前回调未公开勾选状态；读取其主视图持有的 Store，SDK 变更时由导出大小兜底。
    internal fun isSendingOriginal(): Boolean? {
        val mainView = pickerView?.getChildAt(0) ?: return null
        return runCatching {
            val field = mainView.javaClass.declaredFields
                .singleOrNull { it.type == AlbumPickerStore::class.java }
                ?: return@runCatching null
            field.isAccessible = true
            val store = field.get(mainView) as? AlbumPickerStore
            store?.state?.isOriginalSelected?.value
        }.getOrNull()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (currentInstance == this) {
            currentInstance = null
        }
        AlbumPickerHandler.cleanup()
    }
}
