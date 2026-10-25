import 'dart:io';
import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';

import '../../../file_picker/file_picker.dart';
import '../../../message_input/chat_media_sender.dart';
import '../../message_list_config.dart';
import '../../utils/big_file_message.dart';

/// 普通文件与大文件共用卡片；业务下载交给宿主，SDK文件沿原生下载边界处理。
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
      this.bigFile});

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

  /// 定位高亮时覆盖背景，不改变文件信息布局。
  final Color? bubbleColor;

  /// 已校验的大文件协议；为空时读取SDK文件负载。
  final BigFileMessage? bigFile;
  @override
  State<FileMessageWidget> createState() => _FileMessageWidgetState();
}

/// 只管理当前卡片的打开动作和资源失效显示，上传状态来自宿主Controller。
class _FileMessageWidgetState extends State<FileMessageWidget> {
  bool _opening = false;

  /// 仅明确资源失效时锁定，网络异常不改变此值。
  bool _expired = false;

  /// 本次成功下载的路径；持久化与账号隔离由宿主下载服务负责。
  String? _localPath;

  FileMessagePayload? get _payload =>
      widget.message.messagePayload is FileMessagePayload
          ? widget.message.messagePayload as FileMessagePayload
          : null;
  String get _name => widget.bigFile?.name ?? _payload?.fileName ?? '';
  int get _size => widget.bigFile?.size ?? _payload?.fileSize ?? 0;

  /// 一次点击完成下载并打开，403与断网保留重试，不判为过期。
  Future<void> _open() async {
    if (_opening ||
        _expired ||
        widget.config.fileTransfers.containsKey(widget.message.msgID)) {
      return;
    }
    setState(() => _opening = true);
    try {
      var path = _localPath ?? _payload?.filePath;
      if (path == null || !await File(path).exists()) {
        final file = widget.bigFile;
        if (file != null) {
          final download = widget.config.fileDownloader;
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
      if (!mounted) return;
      if (!await FilePicker.openFile(path) && mounted) {
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
    final status = _expired
        ? AppLocalization.of(context).appFileExpired
        : transfer?.interrupted == true
            ? AppLocalization.of(context).appFileInterrupted
            : failed
                ? AppLocalization.of(context).appFileFailed
                : null;
    final progress = transfer?.progress ??
        (sending && transfer == null
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
      identifier: 'tim.fileMessage.open.${widget.message.msgID}',
      button: true,
      enabled: !_expired && transfer == null,
      child: GestureDetector(
        onTap: _open,
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
                        // 大小独立保留，异常文案只占其后的剩余空间。
                        Row(children: [
                          Text(formatChatFileSize(_size),
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 20 / 14,
                                  color: _expired
                                      ? colors.textTertiary
                                      : colors.textSecondary)),
                          if (status != null) ...[
                            const SizedBox(width: 4),
                            Flexible(
                                child: Text(status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        height: 20 / 14,
                                        color: _expired
                                            ? colors.textTertiary
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
                      value: _opening ? null : progress?.clamp(0, 1),
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
