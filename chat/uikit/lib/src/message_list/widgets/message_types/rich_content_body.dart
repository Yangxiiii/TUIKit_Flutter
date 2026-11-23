part of 'custom_message_widget.dart';

/// 按接收顺序渲染聊天、回复详情和独立页面中的同一份图文正文。
final class RichContentBody extends StatelessWidget {
  const RichContentBody({
    super.key,
    required this.content,
    required this.textStyle,
    required this.maxMediaWidth,
    required String semanticsPrefix,
    this.config = const ChatMessageListConfig(),
  })  : standalone = true,
        message = null,
        _conversationMedia = null,
        isSelf = false,
        receipt = null,
        localPreview = false,
        _mediaRadius = 4,
        _standaloneSemantics = semanticsPrefix;

  const RichContentBody._({
    required this.content,
    required this.textStyle,
    required this.maxMediaWidth,
    required this.message,
    required ({
      String conversationId,
      List<MessageInfo>? presetMessages,
      ChatOlderMessagesLoader? loadOlderMedia,
    })? conversationMedia,
    required this.config,
    required this.isSelf,
    required this.receipt,
    required this.localPreview,
    required double mediaRadius,
  })  : standalone = false,
        _conversationMedia = conversationMedia,
        _mediaRadius = mediaRadius,
        _standaloneSemantics = null;

  /// 已通过聊天协议边界校验且保留原顺序的内容块。
  final RichContentMessage content;

  /// 由外层容器决定正文颜色与基础字号。
  final TextStyle textStyle;

  /// 当前容器允许的媒体宽度，单位为逻辑像素。
  final double maxMediaWidth;

  /// 聊天消息提供提及位置和媒体标识；公告正文没有消息上下文。
  final MessageInfo? message;

  /// 聊天媒体使用当前会话范围，独立正文只展示自身附件。
  final ({
    String conversationId,
    List<MessageInfo>? presetMessages,
    ChatOlderMessagesLoader? loadOlderMedia,
  })? _conversationMedia;

  /// 沿用宿主的缩略图、下载及提及处理。
  final MessageListConfigProtocol config;

  final bool isSelf;

  /// 回复详情中的回执附在最后一个文字块，公告无需回执。
  final Widget? receipt;

  /// 仅发送中的聊天草稿允许访问本地文件。
  final bool localPreview;

  /// 独立页面保留内容的标题和媒体原始尺寸。
  final bool standalone;
  final double _mediaRadius;

  /// 页面传入的稳定语义命名空间，不包含签名地址。
  final String? _standaloneSemantics;

  String get _semanticsPrefix =>
      _standaloneSemantics ?? 'tim.rich.${message?.msgID}';

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final foreground = textStyle.color ?? colors.textColorPrimary;
    final receipt = this.receipt;
    final receiptIndex = receipt == null
        ? -1
        : content.blocks.lastIndexWhere((block) => block is RichTextBlock);
    final fileOccurrences = <int, int>{};
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 每个块保留原始位置，避免把附件统一挪到文字之后。
        for (final (index, block) in content.blocks.indexed) ...[
          if (index > 0) const SizedBox(height: 8),
          switch (block) {
            RichTextBlock(:final text, :final title) => standalone && title
                ? _buildTitleBlock(text)
                : _buildRichText(text, textStyle, index,
                    index == receiptIndex ? receipt : null),
            RichImageBlock(:final url, :final width, :final height) =>
              _buildImage(
                context,
                url,
                width,
                height,
                colors,
                localPreview ? null : () => _openMedia(context, index),
                localPreview: localPreview,
              ),
            RichFileBlock(
              :final url,
              :final mimeType,
              :final thumbnailUrl,
              :final width,
              :final height,
              :final videoDuration,
            )
                when mimeType.startsWith('video/') =>
              _buildVideo(
                context,
                url,
                thumbnailUrl,
                width,
                height,
                localPreview ? null : () => _openMedia(context, index),
                localPreview: localPreview,
                videoDuration: videoDuration,
              ),
            RichFileBlock file =>
              _buildFile(file, foreground, colors, fileOccurrences),
          },
        ],
        if (receipt != null && receiptIndex < 0) receipt,
      ],
    );
  }

  /// 从点中的块打开会话媒体，独立正文保留自己的附件范围。
  Future<void> _openMedia(BuildContext context, int index) async {
    final media = _conversationMedia;
    final source = message;
    if (media == null || source == null) {
      showRichContentMediaViewer(context, content, index,
          downloadVideo: config.fileDownloader);
      return;
    }
    final manager = ImageViewerManager(
      conversationID: media.conversationId,
      currentMessage: source,
      context: context,
      presetMediaMessages: media.presetMessages,
      hiddenMessageIDs: config.hiddenMessageIDs,
      downloadRichVideo: config.fileDownloader,
      loadOlderMedia: media.loadOlderMedia,
    );
    try {
      await manager.showRichContent(context, content, index);
    } finally {
      manager.dispose();
    }
  }

  /// 聊天编辑器用空行分隔标题和同一块正文，只放大标题所在段落。
  Widget _buildTitleBlock(String text) {
    final split = text.indexOf('\n\n');
    final titleStyle =
        textStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w600);
    if (split < 0)
      return RichContentMarkdown(data: text, textStyle: titleStyle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichContentMarkdown(
            data: text.substring(0, split), textStyle: titleStyle),
        const SizedBox(height: 4),
        RichContentMarkdown(
            data: text.substring(split + 2), textStyle: textStyle),
      ],
    );
  }

  /// 回执与正文同一行，长正文保留折行，后续图片继续独立占行。
  Widget _buildRichText(
      String text, TextStyle style, int index, Widget? receipt) {
    final source = message;
    final mentionReceiptBuilder = config.mentionReceiptBuilder;
    final body = RichContentMarkdown(
      data: text,
      textStyle: style,
      mentions: message == null
          ? const []
          : MessageMentions.read(message!, text, index),
      onMentionTap: config.onMentionTap,
      highlightedMentionUserId:
          isSelf ? null : incomingGroupMentionUserId(source),
      buildMentionReceipt: source == null || mentionReceiptBuilder == null
          ? null
          : (userId) => mentionReceiptBuilder(source, userId),
    );
    if (receipt == null) return body;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [Flexible(child: body), const SizedBox(width: 8), receipt],
    );
  }

  /// 按原图比例约束气泡尺寸，点击进入媒体预览，加载失败时保留可识别占位。
  Widget _buildImage(
    BuildContext context,
    String url,
    int? width,
    int? height,
    SemanticColorScheme colors,
    VoidCallback? onPreview, {
    bool localPreview = false,
  }) {
    final size = width != null && height != null
        ? _mediaDisplaySize(width, height)
        : null;
    final displayWidth = size?.width ?? _mediaWidth;
    // 无尺寸消息交由图片解码确定比例，仍限制最大高度，避免长图撑满聊天窗口。
    final displayHeight = size?.height;
    return Semantics(
      identifier: '$_semanticsPrefix.image.${url.hashCode}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPreview,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_mediaRadius),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: displayWidth, maxHeight: 240),
            child: Image(
              image: _resizeMediaImage(
                context,
                localPreview && Uri.tryParse(url)?.scheme == 'file'
                    ? FileImage(File.fromUri(Uri.parse(url)))
                    : CachedNetworkImageProvider(url),
                Size(displayWidth, displayHeight ?? 240),
              ),
              width: displayWidth,
              height: displayHeight,
              fit: BoxFit.contain,
              frameBuilder: (_, child, frame, synchronous) =>
                  synchronous || frame != null
                      ? child
                      : _buildImagePlaceholder(displayWidth, displayHeight),
              errorBuilder: (_, __, ___) => SizedBox(
                width: displayWidth,
                height: displayHeight ?? 120,
                child: Icon(Icons.broken_image_outlined,
                    color: colors.textColorTertiary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 消息携带尺寸时，加载占位和资源共用同一个盒子，避免加载完成后气泡跳动。
  Widget _buildImagePlaceholder(double width, double? height) => SizedBox(
        width: width,
        height: height ?? 120,
        child: ChatMediaPlaceholder(
          image: config.imageLoadingPlaceholder,
          showLoading: config.imageLoadingPlaceholder == null,
        ),
      );

  /// 宽高只用于比例，在气泡的宽高上限内等比缩放，避免长图或竖屏视频被裁剪。
  Size _mediaDisplaySize(int width, int height) => applyBoxFit(
        standalone ? BoxFit.scaleDown : BoxFit.contain,
        Size(width.toDouble(), height.toDouble()),
        Size(_mediaWidth, 240),
      ).destination;

  /// 独立正文沿用媒体原尺寸，回复详情保留既有 208 宽度上限。
  double get _mediaWidth => math.max(1.0, maxMediaWidth);

  /// 与编辑器一致，按展示物理像素的 1.5 倍解码；保持比例且不放大小图。
  ResizeImage _resizeMediaImage(
      BuildContext context, ImageProvider original, Size size) {
    final scale = MediaQuery.devicePixelRatioOf(context) * 1.5;
    return ResizeImage(
      original,
      width: math.max(1, (size.width * scale).ceil()),
      height: math.max(1, (size.height * scale).ceil()),
      policy: ResizeImagePolicy.fit,
    );
  }

  /// 视频气泡点击进入共用媒体预览器，编辑器中的封面仍不提供播放交互。
  Widget _buildVideo(BuildContext context, String url, String? thumbnailUrl,
      int? width, int? height, VoidCallback? onPreview,
      {bool localPreview = false, int? videoDuration}) {
    // 历史视频没有尺寸时沿用横屏占位，新消息在解码封面前即可确定真实比例。
    final size = width != null && height != null
        ? _mediaDisplaySize(width, height)
        : applyBoxFit(BoxFit.contain, const Size(16, 9), Size(_mediaWidth, 240))
            .destination;
    // 消息与资源共同区分点击入口，资源地址只保留散列，避免把签名URL写入语义树。
    return Semantics(
      identifier: '$_semanticsPrefix.video.${url.hashCode}',
      child: GestureDetector(
        // 封面自身忽略指针以兼容编辑器，气泡需要由外层显式接管点击命中。
        behavior: HitTestBehavior.opaque,
        onTap: onPreview,
        child: RichContentVideoPreview(
          playIcon: config.videoPlayIcon,
          showInlineDuration: standalone,
          durationMs: videoDuration == null
              ? null
              : videoDuration * Duration.millisecondsPerSecond,
          loadingPlaceholder: config.videoLoadingPlaceholder,
          image: thumbnailUrl == null
              ? null
              : _resizeMediaImage(
                  context,
                  localPreview && Uri.tryParse(thumbnailUrl)?.scheme == 'file'
                      ? FileImage(File.fromUri(Uri.parse(thumbnailUrl)))
                      : CachedNetworkImageProvider(thumbnailUrl),
                  size,
                ),
          size: size,
        ),
      ),
    );
  }

  /// 聊天附件复用独立文件卡片和会话下载，公告中的外链继续交给系统打开。
  Widget _buildFile(
    RichFileBlock file,
    Color foreground,
    SemanticColorScheme colors,
    Map<int, int> fileOccurrences,
  ) {
    final source = message;
    if (source == null) {
      return _buildAnnouncementFile(file, foreground, colors);
    }

    // 仅暴露地址散列，并用相同散列的出现次数区分一条消息中重复插入的附件。
    final hash = file.url.hashCode;
    final occurrence =
        fileOccurrences.update(hash, (count) => count + 1, ifAbsent: () => 1);
    final identifier = '$_semanticsPrefix.file.$hash.$occurrence';
    return FileMessageWidget(
      key: ValueKey((identifier, file.url, file.name, file.size)),
      message: source,
      isSelf: isSelf,
      maxWidth: _mediaWidth,
      config: config,
      attachment: (
        file: BigFileMessage(url: file.url, name: file.name, size: file.size),
        semanticsIdentifier: identifier,
        localPreview: localPreview,
      ),
    );
  }

  /// 独立公告没有聊天消息上下文，保留原有附件布局与打开方式。
  Widget _buildAnnouncementFile(
    RichFileBlock file,
    Color foreground,
    SemanticColorScheme colors,
  ) {
    return InkWell(
      // 公告未接入会话文件服务，仍把已校验的远端地址交给系统处理。
      onTap: () =>
          launchUrl(Uri.parse(file.url), mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelf
              ? colors.buttonColorPrimaryDefault.withAlpha(26)
              : colors.bgColorDefault.withAlpha(128),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 公告附件沿用通用标识，文件名和大小在剩余宽度内展示。
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.buttonColorSecondaryHover,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.attach_file,
                color: colors.textColorAntiPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        FontScheme.caption2Medium.copyWith(color: foreground),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatChatFileSize(file.size),
                    style: FontScheme.caption3Regular.copyWith(
                      color: isSelf
                          ? colors.textColorAntiSecondary
                          : colors.textColorSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
