import 'dart:math';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/services.dart';

import '../emoji_picker/emoji_manager.dart';
import '../message_list/utils/rich_content_markdown_parser.dart';
import '../message_list/utils/rich_content_markdown_format.dart';
import '../message_list/utils/rich_content_message.dart';
import 'mention/mention_info.dart';
import 'message_input_config.dart';
import 'rich_content_draft.dart';

/// 将聊天消息拆成系统可见的纯文本与应用内可还原的草稿。
final class CopiedChatMessage {
  /// 系统剪贴板和其他应用读取的可见文字。
  final String preview;

  /// 普通正文或业务表情原始令牌。
  final String text;

  /// 图文原文及有序附件，由现有草稿渲染和发送。
  final RichContentDraft? richDraft;

  /// 原消息的提及目标，粘贴时还需按目标会话校验。
  final List<String> atUserIds;

  const CopiedChatMessage._(
      this.preview, this.text, this.richDraft, this.atUserIds);

  /// 返回复制菜单支持的消息类型；普通自定义消息仍走各自的业务动作。
  static bool supports(MessagePayload? payload) => switch (payload) {
        TextMessagePayload() ||
        FaceMessagePayload() ||
        ImageMessagePayload() ||
        VideoMessagePayload() =>
          true,
        CustomMessagePayload() => _richMessage(payload) != null,
        _ => false,
      };

  /// 快照原文和远端媒体信息，避免复制后受列表下载回调修改。
  static CopiedChatMessage? fromMessage(MessageInfo message) {
    final payload = message.messagePayload;
    final rich = _richMessage(payload);
    final text = switch (payload) {
      TextMessagePayload() => payload.text,
      FaceMessagePayload() => payload.faceData ?? '',
      _ => '',
    };
    // 腾讯图片和视频与应用图文统一还原为草稿附件，系统只接收可见占位。
    final preview = switch (payload) {
      TextMessagePayload() => richContentMarkdownToPlainText(text),
      ImageMessagePayload() => '[图片]',
      VideoMessagePayload() => '[视频]',
      FaceMessagePayload() when text.isEmpty => '[表情]',
      _ => rich?.blocks.map(_plainBlock).join('\n') ?? text,
    };
    if (preview.isEmpty) return null;
    return CopiedChatMessage._(
      preview.replaceAllMapped(EmojiManager.tokenPattern,
          (match) => '[${EmojiManager.getEmoji(match[0]!)!.label}]'),
      text,
      rich == null
          ? _localMediaDraft(payload)
          : RichContentDraft.fromMessage(rich),
      List.unmodifiable(message.atUserList),
    );
  }

  /// 提取支持复用的远端媒体；未知自定义消息和缺少地址的媒体仅可复制其占位。
  static RichContentMessage? _richMessage(MessagePayload? payload) {
    final RichContentBlock? block;
    // 腾讯旧消息以 0 表示缺少尺寸，草稿持久化使用 null 表示同一状态。
    switch (payload) {
      case CustomMessagePayload():
        return RichContentMessage.tryParse(payload.customData);
      case ImageMessagePayload():
        final url = [
          payload.originalImageURL,
          payload.largeImageURL,
          payload.thumbImageURL
        ].whereType<String>().where(isValidRichContentUrl).firstOrNull;
        if (url == null) return null;
        block = RichImageBlock(
            url,
            _positiveDimension(payload.originalImageWidth),
            _positiveDimension(payload.originalImageHeight));
      case VideoMessagePayload():
        final url = payload.videoURL;
        if (url == null || !isValidRichContentUrl(url)) return null;
        final type = payload.videoType?.toLowerCase();
        final extension = type != null && RegExp(r'^[a-z0-9]+$').hasMatch(type)
            ? type
            : 'mp4';
        block = RichFileBlock(
            url, 'video.$extension', payload.videoSize, 'video/$extension',
            thumbnailUrl: isValidRichContentUrl(payload.videoSnapshotURL)
                ? payload.videoSnapshotURL
                : null,
            width: _positiveDimension(payload.videoSnapshotWidth),
            height: _positiveDimension(payload.videoSnapshotHeight),
            videoDuration:
                payload.videoDuration > 0 ? payload.videoDuration : null);
      default:
        return null;
    }
    return RichContentMessage([block]);
  }

  /// 本地发送记录未取得远端地址时，沿用草稿已有的本地预览与上传流程。
  static RichContentDraft? _localMediaDraft(MessagePayload? payload) {
    final attachment = switch (payload) {
      ImageMessagePayload(originalImagePath: final String path)
          when path.startsWith('/') =>
        RichContentLocalAttachment(
          type: RichContentAttachmentType.image,
          localPath: path,
          fileName: Uri.file(path).pathSegments.lastOrNull ?? 'media',
          fileSize: payload.originalImageSize,
          mimeType: 'image/*',
          width: _positiveDimension(payload.originalImageWidth),
          height: _positiveDimension(payload.originalImageHeight),
        ),
      VideoMessagePayload(videoPath: final String path)
          when path.startsWith('/') =>
        RichContentLocalAttachment(
          type: RichContentAttachmentType.file,
          localPath: path,
          fileName: Uri.file(path).pathSegments.lastOrNull ?? 'media',
          fileSize: payload.videoSize,
          mimeType: 'video/mp4',
          thumbnailPath: payload.videoSnapshotPath,
          width: _positiveDimension(payload.videoSnapshotWidth),
          height: _positiveDimension(payload.videoSnapshotHeight),
          durationMs: _videoDurationMs(payload.videoDuration),
        ),
      _ => null,
    };
    if (attachment == null) return null;
    return RichContentDraft(
      blocks: [RichContentDraftAttachmentBlock(0, attachment: attachment)],
    );
  }

  static int? _positiveDimension(int value) => value > 0 ? value : null;

  /// SDK 以秒返回视频时长，缺省为 0；草稿使用毫秒并保留未知状态。
  static int? _videoDurationMs(int seconds) =>
      seconds > 0 ? seconds * 1000 : null;

  static String _plainBlock(RichContentBlock block) => switch (block) {
        RichTextBlock() => richContentMarkdownPlainText(block.text),
        RichImageBlock() => '[图片]',
        RichFileBlock() =>
          block.mimeType.startsWith('video/') ? '[视频]' : block.name,
      };
}

/// 将系统剪贴板的条目身份与当前登录账号内的结构化消息快照绑定。
final class MessageClipboard {
  /// 原生通道只交接可见纯文本与条目身份。
  static const _channel = MethodChannel('tencent_chat_uikit');

  /// 只保留最近一次复制的消息；账号切换或剪贴板条目替换时不能读取。
  static ({
    String token,
    String? account,
    String conversation,
    CopiedChatMessage message
  })? _entry;

  /// 写入纯文本和随机身份；平台剪贴板不保存消息原文、媒体地址或提及目标。
  static Future<void> copy(
      CopiedChatMessage message, String conversation) async {
    final random = Random.secure();
    final token = List.generate(4, (_) => random.nextInt(1 << 32)).join('-');
    _entry = (
      token: token,
      account: LoginStore.shared.loginState.loginUserInfo?.userID,
      conversation: conversation,
      message: message,
    );
    try {
      await _channel.invokeMethod<void>('writeMessageClipboard', {
        'text': message.preview,
        'token': token,
      });
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: message.preview));
    } on PlatformException {
      await Clipboard.setData(ClipboardData(text: message.preview));
    }
  }

  /// 确认系统键盘提交了完整的复制预览，再定位输入格式化后的实际替换范围。
  static TextSelection? richPreviewSelection(
    TextEditingValue before,
    TextEditingValue submitted,
    TextEditingValue applied,
  ) {
    final message = _entry?.message;
    final selection = before.selection;
    if (message == null ||
        (message.richDraft == null &&
            (message.text.isEmpty || message.text == message.preview)) ||
        !before.composing.isCollapsed ||
        !submitted.composing.isCollapsed ||
        !selection.isValid ||
        selection.end > before.text.length) {
      return null;
    }
    // 用键盘原始提交识别预览，当前工具条的格式不能参与条目匹配。
    final start = selection.start;
    final end = start + message.preview.length;
    if (before.text == submitted.text ||
        !submitted.selection.isCollapsed ||
        submitted.selection.extentOffset != end ||
        submitted.text !=
            before.text.replaceRange(start, selection.end, message.preview)) {
      return null;
    }

    // 仅替换本次插入的内容及格式包装，选区外的原文必须保持一致。
    final suffix = before.text.substring(selection.end);
    final appliedEnd = applied.text.length - suffix.length;
    if (appliedEnd <= start ||
        !applied.text.startsWith(before.text.substring(0, start)) ||
        !applied.text.endsWith(suffix)) {
      return null;
    }
    return TextSelection(baseOffset: start, extentOffset: appliedEnd);
  }

  /// 只有原生剪贴板身份仍匹配时才返回原格式，其他条目由输入框按普通文本粘贴。
  static Future<({CopiedChatMessage message, bool sameConversation})?> read(
      String conversation) async {
    final entry = _entry;
    if (entry == null) return null;
    final String? token;
    try {
      token = await _channel.invokeMethod<String>('readMessageClipboardToken');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    // 读取期间可能发生另一次复制或切换账号，迟到的结果不得恢复旧消息。
    if (!identical(_entry, entry) ||
        token != entry.token ||
        LoginStore.shared.loginState.loginUserInfo?.userID != entry.account) {
      return null;
    }
    return (
      message: entry.message,
      sameConversation: conversation == entry.conversation,
    );
  }
}

/// 将可见的 @ 名称与群成员身份匹配，保留空格昵称并跳过无法消歧的同名成员。
List<MentionInfo> matchCopiedMentions(
    String text, Map<String, Set<String>> namesByUser) {
  final matches = <MentionInfo>[];
  // SDK 仅返回提及 ID，没有正文范围；每个 ID 只有一个无歧义位置时才恢复通知。
  for (final entry in namesByUser.entries) {
    final candidates = <MentionInfo>[];
    for (final name in entry.value.where((name) => name.isNotEmpty)) {
      final pattern = RegExp('(?<![\\w/])@${RegExp.escape(name)}(?= |\$)');
      for (final match in pattern.allMatches(text)) {
        candidates.add(MentionInfo(
          userID: entry.key,
          displayName: name,
          startIndex: match.start,
        ));
      }
    }
    if (candidates.length == 1) matches.add(candidates.single);
  }
  return matches
      .where((match) => !matches.any((other) =>
          !identical(match, other) &&
          match.startIndex < other.endIndex &&
          other.startIndex < match.endIndex))
      .toList();
}
