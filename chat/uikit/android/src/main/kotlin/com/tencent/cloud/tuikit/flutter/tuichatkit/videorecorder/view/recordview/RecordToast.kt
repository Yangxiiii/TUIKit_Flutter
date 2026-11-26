package com.tencent.cloud.tuikit.flutter.tuichatkit.videorecorder.view.recordview

import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** 在原生录像窗口的绘制层展示单条提示，触摸继续交给录像控件。 */
internal class RecordToast {
    /** 当前录像窗口与其绘制节点，销毁时一并释放。 */
    private var container: ViewGroup? = null
    private var bubble: TextView? = null

    /** 新提示复用当前视图并更新停留时间，相同文案沿用原计时。 */
    private val fadeOut = Runnable {
        val current = bubble ?: return@Runnable
        current.animate().alpha(0f).setDuration(150).withEndAction {
            if (bubble === current) clear()
        }.start()
    }

    /** 根视图尺寸或键盘变化时，用录像窗口的实际尺寸重新摆放。 */
    private val placeOnLayout = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
        val root = container
        val current = bubble
        if (root != null && current != null) place(root, current)
    }

    fun show(source: View, text: CharSequence) {
        val root = source.rootView as? ViewGroup ?: return
        if (container !== root) clear()
        val existing = bubble
        if (text == existing?.text) return
        val current = existing ?: TextView(root.context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            includeFontPadding = false
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(16), dp(10), dp(16), dp(10))
            background = GradientDrawable().apply {
                // 原生录像窗口没有 Flutter 主题，提示承载面与公共胶囊使用同一深色。
                setColor(Color.rgb(26, 31, 38))
                cornerRadius = dp(999).toFloat()
            }
            alpha = 0f
            translationY = dp(8).toFloat()
        }
        current.text = text
        container = root
        bubble = current
        place(root, current)
        if (existing == null) {
            root.overlay.add(current)
            root.addOnLayoutChangeListener(placeOnLayout)
            current.animate().alpha(1f).translationY(0f).setDuration(200).start()
        } else if (current.translationY == 0f) {
            // 退场中的提示也直接更换文字，避免重复从底部进入。
            current.animate().cancel()
            current.alpha = 1f
        }
        root.removeCallbacks(fadeOut)
        root.postDelayed(fadeOut, 2000)
    }

    /** 录像控件退出时清理独立窗口的视图和计时。 */
    fun clear() {
        val root = container
        val current = bubble
        container = null
        bubble = null
        root?.removeCallbacks(fadeOut)
        root?.removeOnLayoutChangeListener(placeOnLayout)
        current?.animate()?.cancel()
        if (root != null && current != null) root.overlay.remove(current)
    }

    /** 原生录像页没有首页底栏，按整屏或键盘上沿计算底边距。 */
    private fun place(root: ViewGroup, current: TextView) {
        val maxWidth = min(root.width - current.dp(48), (current.textSize * 15).toInt() + current.dp(32))
        if (maxWidth <= 0) return
        current.gravity = if (current.paint.measureText(current.text.toString()) > maxWidth - current.dp(32)) {
            Gravity.LEFT
        } else {
            Gravity.CENTER
        }
        current.measure(
            View.MeasureSpec.makeMeasureSpec(maxWidth, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        val keyboard = ViewCompat.getRootWindowInsets(root)?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0
        val bottom = root.height - max(current.dp(80), if (keyboard > 0) keyboard + current.dp(16) else 0)
        val left = (root.width - current.measuredWidth) / 2
        current.layout(left, bottom - current.measuredHeight, left + current.measuredWidth, bottom)
    }

    private fun View.dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()
}
