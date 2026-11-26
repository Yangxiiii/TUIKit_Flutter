import 'dart:io';
import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../file_picker/file_picker.dart';
import '../../../message_input/chat_media_sender.dart';
import '../../message_list_config.dart';
import '../../utils/big_file_message.dart';

/// 普通文件、大文件和图文附件共用卡片，远端业务文件由宿主下载。
class FileMessageWidget extends StatefulWidget {
  const FileMessageWidget(
      {super.key,
      required this.message,
      required this.isSelf,
      required this.maxWidth,
      required this.config,
      this.onLongPress,
      this.messageListStore,
      this.bubbleKey,
      this.isInMergedDetailView = false,
      this.bubbleColor,
      this.bigFile,
      this.attachment});

  /// SDK消息或上传占位；不把自定义消息伪装成SDK文件元素。
  final MessageInfo message;

  /// 消息在本人发送侧时为true。
  final bool isSelf;

  /// 消息行可用宽度，卡片不得侵入头像区域。
  final double maxWidth;

  /// 宿主提供图片、下载和本地传输状态。
  final MessageListConfigProtocol config;

  /// 沿用消息列表长按菜单。
  final VoidCallback? onLongPress;

  /// 保留SDK消息列表上下文供已有调用方使用。
  final MessageListStore? messageListStore;

  /// 列表用于定位卡片的Key。
  final GlobalKey? bubbleKey;

  /// 合并消息详情继续复用同一卡片。
  final bool isInMergedDetailView;

  /// 可选的文件气泡底色；未提供时沿用收发方向的主题色。
  final Color? bubbleColor;

  /// 已校验的独立大文件协议，提供 SDK 文件元素以外的下载信息。
  final BigFileMessage? bigFile;

  /// 已校验的图文附件使用独立语义标识，发送草稿仅展示文件信息。
  final ({
    BigFileMessage file,
    String semanticsIdentifier,
    bool localPreview
  })? attachment;

  @override
  State<FileMessageWidget> createState() => _FileMessageWidgetState();
}

/// 展示文件导出和上传状态，管理卡片打开动作及资源失效反馈。
class _FileMessageWidgetState extends State<FileMessageWidget> {
  /// 一个卡片只接受一次在途打开操作，结束后允许再次点击。
  bool _opening = false;

  /// 仅明确资源失效时锁定，网络异常不改变此值。
  bool _expired = false;

  /// 本次成功下载的路径；持久化与账号隔离由宿主下载服务负责。
  String? _localPath;

  FileMessagePayload? get _payload =>
      widget.message.messagePayload is FileMessagePayload
          ? widget.message.messagePayload as FileMessagePayload
          : null;

  /// 图文附件和独立大文件均由宿主按 URL 下载。
  BigFileMessage? get _remoteFile => widget.attachment?.file ?? widget.bigFile;

  String get _name => _remoteFile?.name ?? _payload?.fileName ?? '';
  int get _size => _remoteFile?.size ?? _payload?.fileSize ?? 0;

  /// 等导出与发送结束后才允许打开，403 与断网保留重试，不判为过期。
  Future<void> _open() async {
    if (_opening ||
        _expired ||
        widget.attachment?.localPreview == true ||
        widget.message.status == MessageStatus.sending ||
        widget.config.fileTransfers.containsKey(widget.message.msgID)) {
      return;
    }
    setState(() => _opening = true);
    try {
      // 优先打开本地文件，缺失时按文件来源调用对应下载入口。
      var path = _localPath ?? _payload?.filePath;
      if (path == null || !await File(path).exists()) {
        final file = _remoteFile;
        if (file != null) {
          final download = widget.config.fileDownloader;
          if (download == null && widget.attachment != null) {
            // 转发预览等未注入下载服务的宿主仍支持打开原有附件链接。
            final launched = await launchUrl(Uri.parse(file.url),
                mode: LaunchMode.externalApplication);
            if (!launched && mounted) {
              AppToast.show(AppLocalization.of(context).appFileOpenFailed);
            }
            return;
          }
          if (download == null) throw StateError('未配置文件下载');
          path = await download(file);
        } else {
          final result =
              await MessageActionStore.create(widget.message).downloadMedia();
          if (!result.isSuccess) throw StateError('文件下载失败');
          path = _payload?.filePath;
        }
      }
      if (path == null || !await File(path).exists()) throw StateError('文件不可用');
      _localPath = path;
      // 页面已离开时保留下载缓存，跳过系统打开动作。
      if (!mounted) return;
      if (!await FilePicker.openFile(path,
              fileName: _name, canOpen: () => mounted) &&
          mounted) {
        AppToast.show(AppLocalization.of(context).appFileOpenFailed);
      }
    } on ChatFileExpiredException {
      if (mounted) {
        setState(() => _expired = true);
        AppToast.show(AppLocalization.of(context).appFileExpiredHint);
      }
    } on Object {
      if (mounted) {
        AppToast.show(AppLocalization.of(context).appFileDownloadFailed);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final transfer = widget.config.fileTransfers[widget.message.msgID];
    final failed = transfer?.failed == true ||
        widget.message.status == MessageStatus.sendFail;
    final sending = transfer != null && !failed ||
        widget.message.status == MessageStatus.sending;
    final canOpen = !_expired &&
        !sending &&
        transfer == null &&
        widget.attachment?.localPreview != true;
    // 相册导出阶段尚无本地路径，用持续动画提示处理中，不把未知大小显示为 0 B。
    final preparing = sending &&
        transfer == null &&
        _payload != null &&
        _payload?.filePath?.isNotEmpty != true;
    final showSize = !preparing || _size > 0;
    final status = _expired
        ? AppLocalization.of(context).appFileExpired
        : transfer?.interrupted == true
            ? AppLocalization.of(context).appFileInterrupted
            : failed
                ? AppLocalization.of(context).appFileFailed
                : preparing
                    ? AppLocalization.of(context)
                        .resolve(LocaleKeys.common_loading, '加载中…')
                    : null;
    final progress = transfer?.progress ??
        (sending && transfer == null && widget.attachment == null
            ? widget.message.uploadMediaProgress / 100
            : null);
    final nameColor = _expired ? colors.textTertiary : colors.textPrimary;
    final icon = widget.config.fileIconBuilder?.call(context, _name) ??
        SizedBox(
            width: 44,
            height: 44,
            child: Center(
                child: Text(_name.split('.').last.toUpperCase(), maxLines: 1)));

    return Semantics(
      identifier: widget.attachment?.semanticsIdentifier ??
          'tim.fileMessage.open.${widget.message.msgID}',
      button: true,
      enabled: canOpen,
      child: GestureDetector(
        onTap: canOpen ? _open : null,
        onLongPress: widget.onLongPress,
        child: Container(
          key: widget.bubbleKey, width: math.min(284, widget.maxWidth),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: widget.bubbleColor ?? colors.surface,
              border: Border.all(color: colors.outline),
              borderRadius: BorderRadius.circular(8)),
          // 进度条附着卡片底边，文件图标和名称始终保留。
          child: Stack(children: [
            Padding(
                // Container将1px边框计入内边距，总留白保持设计的12px。
                padding: const EdgeInsets.all(11),
                child: Row(children: [
                  if (_expired)
                    // 失效状态保留原资产轮廓并去色，不能只降低彩色图标透明度。
                    Opacity(
                        opacity: .4,
                        child: ColorFiltered(
                            colorFilter: const ColorFilter.matrix([
                              .2126,
                              .7152,
                              .0722,
                              0,
                              0,
                              .2126,
                              .7152,
                              .0722,
                              0,
                              0,
                              .2126,
                              .7152,
                              .0722,
                              0,
                              0,
                              0,
                              0,
                              0,
                              1,
                              0,
                            ]),
                            child: icon))
                  else
                    icon,
                  const SizedBox(width: 8),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(_name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                height: 20 / 14,
                                color: nameColor)),
                        const SizedBox(height: 4),
                        // 已知大小独立显示，状态文案使用剩余空间。
                        Row(children: [
                          if (showSize)
                            Text(formatChatFileSize(_size),
                                style: TextStyle(
                                    fontSize: 14,
                                    height: 20 / 14,
                                    color: _expired
                                        ? colors.textTertiary
                                        : colors.textSecondary)),
                          if (status != null) ...[
                            if (showSize) const SizedBox(width: 4),
                            Flexible(
                                child: Text(status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        height: 20 / 14,
                                        color: _expired
                                            ? colors.textTertiary
                                            : preparing
                                                ? colors.textSecondary
                                                : colors.danger))),
                          ],
                        ]),
                      ])),
                ])),
            if (sending || _opening)
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                      value:
                          _opening || preparing ? null : progress?.clamp(0, 1),
                      minHeight: 2,
                      color: colors.primary,
                      backgroundColor: Colors.transparent)),
          ]),
        ),
      ),
    );
  }
}

/// 文件卡片保留一位小数；分流始终使用原始字节数。
String formatChatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
