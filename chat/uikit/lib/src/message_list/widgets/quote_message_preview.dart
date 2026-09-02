import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';

/// A quote message preview block shown inside a message bubble.
/// Displays the quoted message's sender name + content summary/thumbnail.
/// Tapping triggers navigation to the quoted message.
///
/// 显示在消息气泡内的引用消息预览块。显示被引用消息的发送者姓名 + 内容摘要/缩略图。点击可导航到引用消息。
class QuoteMessagePreview extends StatelessWidget {
  final MessageQuoteInfo quoteInfo;
  final VoidCallback? onTap;
  final double maxWidth;

  const QuoteMessagePreview({
    super.key,
    required this.quoteInfo,
    this.onTap,
    this.maxWidth = 200,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final locale = AppLocalization.of(context);

    return GestureDetector(
      onTap: () => _handleTap(context, locale),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
        decoration: BoxDecoration(
          color: colors.sliderColorEmpty,
          borderRadius: BorderRadius.circular(6),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Left vertical bar
              //
              // 左侧垂直栏
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: colors.switchColorOff,
                ),
              ),
              // Content area
              //
              // 内容区域
              Flexible(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: _buildContent(colors, locale),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(SemanticColorScheme colors, AppLocalizedText locale) {
    // Display priority — derived from (status, payload) only; no extra
    // "isNotFound" flag is needed because the engine repurposes
    // `status = deleted` to mean "original unreachable" when cloud
    // lookup also fails (see MessageListStoreImpl._fillQuoteInfoFromCloud).
    //
    //   1. `status == revoked`
    //        → "引用内容已撤回". `ChatUtil.getMessagePayload` returns
    //          null for revoked messages by global convention, so this
    //          must come BEFORE any payload-null check.
    //
    //   2. `status == deleted` AND `payload != null`
    //        → render the original payload preview (per product spec:
    //          "if the deleted original message is still loadable, show
    //          its content"). Tap-time navigation is still blocked and
    //          shows "无法定位到原消息" (see `_handleTap`).
    //
    //   3. `status == deleted` AND `payload == null`
    //        → "无法找到引用内容". This is the "unreachable" branch the
    //          engine routes to when both local DB and cloud history
    //          can't find the quoted message anymore.
    //
    //   4. `payload == null` AND status is neither revoked nor deleted
    //        → partial loading placeholder. Engine is still
    //          asynchronously filling quoteInfo.
    //
    //   5. Otherwise → render full original content normally.
    //
    // 显示优先级 —— 仅由 (状态, payload) 派生；不需要额外的 “isNotFound” 标记，因为引擎会重新利用
    //
    // 查找也失败（见 MessageListStoreImpl._fillQuoteInfoFromCloud）。
    //
    // 按照全局约定，被撤回的消息为 null，因此这必须在任何 payload-null 检查之前。
    //
    // → 渲染原始 payload 预览（根据产品规范：“如果已删除的原始消息仍可加载，则显示其内容”）。点击时的导航仍被阻塞，并且
    //
    // 引擎会在本地数据库和云端历史记录都找不到引用消息时进行路由。
    //
    // → 部分加载占位符。引擎仍在异步填充 quoteInfo。
    //
    // 5. 否则 → 正常渲染完整原始内容。
    if (quoteInfo.status == MessageStatus.revoked) {
      return _buildStatusContent(colors, locale.quotedMessageRevoked);
    }
    if (quoteInfo.status == MessageStatus.deleted) {
      if (quoteInfo.messagePayload == null) {
        return _buildStatusContent(colors, locale.quotedMessageNotFound);
      }
      return _buildFullContent(colors, locale);
    }
    if (quoteInfo.messagePayload == null) {
      return _buildPartialContent(colors);
    }
    return _buildFullContent(colors, locale);
  }

  /// Tap handler: gate the upstream `onTap` (navigate-to-original) when
  /// the original message is no longer reachable, and surface a toast
  /// instead.
  ///
  /// Reachability rules:
  ///   - `revoked` → unreachable (server still has the message but it's
  ///     hidden from history navigation by product design)
  ///   - `deleted` → unreachable (either truly deleted by the user, or
  ///     repurposed by the engine to mean "cloud lookup gave up" —
  ///     either way it can't be located in the list)
  ///   - any other state (including partial-loading) → defer to caller
  ///
  /// 点击处理器：在原始消息无法访问时，阻止上游的 `onTap`（导航至原始消息），并显示提示
  ///
  /// 可达性规则：- `revoked` → 无法访问（服务器仍保留消息，但根据产品设计，它在历史记录导航中被隐藏）- `deleted` →
  /// 无法访问（要么被用户真正删除，要么被引擎重新解释为“云端查询放弃”——无论哪种情况，都无法在列表中找到）- 任何其他状态（包括部分加载）→ 由调用方决定
  void _handleTap(BuildContext context, AppLocalizedText locale) {
    final unreachable = quoteInfo.status == MessageStatus.revoked ||
        quoteInfo.status == MessageStatus.deleted;
    if (unreachable) {
      Toast.info(context, locale.quotedOriginalMessageUnreachable);
      return;
    }
    onTap?.call();
  }

  Widget _buildPartialContent(SemanticColorScheme colors) {
    final senderName = _getSenderName();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (senderName.isNotEmpty)
          Text(
            '$senderName:',
            style: FontScheme.caption3Medium.copyWith(
              color: colors.textColorSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 2),
        Text(
          '...',
          style: FontScheme.caption3Regular.copyWith(
            color: colors.textColorSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusContent(SemanticColorScheme colors, String statusText) {
    return Text(
      statusText,
      style: FontScheme.caption3Regular.copyWith(
        color: colors.textColorSecondary,
      ),
    );
  }

  Widget _buildFullContent(
      SemanticColorScheme colors, AppLocalizedText locale) {
    final senderName = _getSenderName();
    final payload = quoteInfo.messagePayload!;
    final thumbnail = _getThumbnailUrl(payload);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (senderName.isNotEmpty)
                Text(
                  '$senderName:',
                  style: FontScheme.caption3Medium.copyWith(
                    color: colors.textColorSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              // When a thumbnail is being rendered alongside (image /
              // video payloads), skip the redundant "[图片]" / "[视频]"
              // text label — the thumbnail itself IS the content
              // summary, and showing both is visual noise.
              //
              // 当缩略图与（图片/
              //
              // 文本标签）一起渲染时——缩略图本身就是内容摘要，同时显示两者会形成视觉干扰。
              if (thumbnail == null) ...[
                const SizedBox(height: 2),
                _buildContentWidget(payload, colors, locale),
              ],
            ],
          ),
        ),
        if (thumbnail != null) ...[
          const SizedBox(width: 8),
          _buildThumbnail(colors, thumbnail),
        ],
      ],
    );
  }

  Widget _buildContentWidget(MessagePayload payload, SemanticColorScheme colors,
      AppLocalizedText locale) {
    final textStyle = FontScheme.caption3Regular.copyWith(
      color: colors.textColorSecondary,
    );

    // Audio and file types use Icon prefix instead of emoji
    //
    // 音频和文件类型使用图标前缀而非表情符号
    switch (payload) {
      case AudioMessagePayload p:
        final duration = p.audioDuration;
        final minutes = duration ~/ 60;
        final seconds = duration % 60;
        final timeText =
            '${minutes > 0 ? "$minutes:" : ""}${seconds.toString().padLeft(2, '0')}"';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.volume_up, size: 14, color: colors.textColorSecondary),
            const SizedBox(width: 2),
            Text(timeText,
                style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        );
      case FileMessagePayload p:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file,
                size: 14, color: colors.textColorSecondary),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                p.fileName ?? locale.messageTypeFile,
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      default:
        // Use ExtendedText so [TUIEmoji_*] tokens render as inline emoji
        // images instead of being shown literally. This matches the bubble
        // rendering and the merged-message preview.
        //
        // 使用 ExtendedText，这样 [TUIEmoji_*] 标记会以内联表情图像渲染，而不是直接显示文字。这与气泡渲染和合并消息预览保持一致。
        return ExtendedText(
          _getContentSummary(payload, locale),
          specialTextSpanBuilder: ChatSpecialTextSpanBuilder(
            colorScheme: colors,
            onTapUrl: (_) {},
          ),
          style: textStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  String _getSenderName() {
    final sender = quoteInfo.sender;
    final name = sender.friendRemark ?? sender.nameCard ?? sender.nickname;
    if (name != null && name.isNotEmpty) return name;
    return sender.userID;
  }

  String _getContentSummary(MessagePayload payload, AppLocalizedText locale) {
    switch (payload) {
      case TextMessagePayload p:
        return p.text;
      case ImageMessagePayload _:
        return locale.messageTypeImage;
      case VideoMessagePayload _:
        return locale.messageTypeVideo;
      case AudioMessagePayload p:
        final duration = p.audioDuration;
        final minutes = duration ~/ 60;
        final seconds = duration % 60;
        return '${minutes > 0 ? "$minutes:" : ""}${seconds.toString().padLeft(2, '0')}"';
      case FileMessagePayload p:
        return p.fileName ?? locale.messageTypeFile;
      case FaceMessagePayload _:
        return locale.messageTypeSticker;
      case CustomMessagePayload p:
        return p.description ?? locale.messageTypeCustom;
      case MergedMessagePayload p:
        return p.title.isNotEmpty ? p.title : locale.messageTypeMerged;
      default:
        return locale.messageTypeUnknown;
    }
  }

  _ThumbnailInfo? _getThumbnailUrl(MessagePayload payload) {
    if (payload is ImageMessagePayload) {
      final url = payload.thumbImageURL ?? payload.originalImageURL;
      if (url != null && url.isNotEmpty) {
        return _ThumbnailInfo(url: url, isVideo: false);
      }
    } else if (payload is VideoMessagePayload) {
      final url = payload.videoSnapshotURL;
      if (url != null && url.isNotEmpty) {
        return _ThumbnailInfo(url: url, isVideo: true);
      }
    }
    return null;
  }

  Widget _buildThumbnail(SemanticColorScheme colors, _ThumbnailInfo info) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: info.url,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                color: colors.bgColorBubbleReciprocal,
                child: Icon(
                  info.isVideo ? Icons.videocam : Icons.image,
                  size: 18,
                  color: colors.textColorSecondary,
                ),
              ),
            ),
            if (info.isVideo)
              Positioned.fill(
                child: Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailInfo {
  final String url;
  final bool isVideo;

  const _ThumbnailInfo({required this.url, required this.isVideo});
}
