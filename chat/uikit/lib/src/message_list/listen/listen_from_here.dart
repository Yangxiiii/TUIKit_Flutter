import 'package:app_ui/app_ui.dart';
import 'package:tuikit_atomic_x/atomicx.dart';

import '../../ai/tts/tts_text_sanitizer.dart';

/// A single unit of the "listen from here" playback queue.
///
/// [speechText] is synthesized via TTS. For voice messages [audioPath] is the
/// original audio to play right after the spoken prefix; null otherwise.
///
/// “从这里开始听”的播放队列中的单个单位。
///
/// [speechText] 通过 TTS 合成。对于语音消息，[audioPath] 是需在语音前缀后直接播放的原始音频；否则为 null。
class ListenItem {
  final String speechText;
  final String? audioPath;

  const ListenItem({required this.speechText, this.audioPath});
}

/// Resolve a non-self speaker's display name (remark > nameCard > nickname > id).
///
/// 解析非本人发言者的显示名称（备注 > 名片 > 昵称 > id）。
String _speakerName(MessageSenderInfo from) {
  for (final candidate in [
    from.friendRemark,
    from.nameCard,
    from.nickname,
    from.userID,
  ]) {
    if (candidate != null && candidate.isNotEmpty) return candidate;
  }
  return from.userID;
}

/// Build the ordered playback plan from [messages] (expected oldest→newest).
///
/// - text: speaks "{prefix}{content}" (prefix includes "said"/「说」).
/// - image/video/file: speaks "{prefix} sent an image/video/file".
/// - audio: speaks "{prefix}" then plays the original audio.
/// - other types and empty text are skipped.
///
/// When the spoken message has the same sender as the previously spoken one,
/// the speaker announcement ("{name}说" / name on media) is omitted so the
/// listener isn't told the same name repeatedly.
///
/// 从 [messages] 构建有序播放计划（按时间顺序从最旧到最新）。
///
/// - 图片/视频/文件：读作“{prefix} 发送了一张图片/视频/文件”。- 音频：先读作“{prefix}”，然后播放原始音频。- 其他类型和空文本则跳过。
///
/// 当语音消息的发送者和上一个语音消息相同时，
///
/// 不会重复告诉听者相同的名字。
List<ListenItem> buildListenPlan({
  required List<MessageInfo> messages,
  required AppLocalizedText l,
}) {
  final items = <ListenItem>[];
  String? lastSpeakerKey;
  for (final m in messages) {
    final isSelf = m.isSentBySelf;
    final speakerKey = isSelf ? '__self__' : m.from.userID;
    final speaker = isSelf ? l.listenSelfSpeaker : _speakerName(m.from);
    final sameAsPrev = lastSpeakerKey != null && lastSpeakerKey == speakerKey;
    switch (m.messageType) {
      case MessageType.text:
        final raw = (m.messagePayload as TextMessagePayload?)?.text ?? '';
        // Strip emoji so they aren't spoken; skip emoji-only messages.
        //
        // 去掉表情符号，这样它们不会被朗读；跳过只有表情符号的消息。
        final content = sanitizeTextForTts(raw);
        if (content.isEmpty) continue;
        items.add(ListenItem(
          speechText: sameAsPrev ? content : l.listenSays(speaker) + content,
        ));
        break;
      case MessageType.image:
        items.add(ListenItem(
          speechText: sameAsPrev
              ? l.listenSentImage('').trim()
              : l.listenSentImage(speaker),
        ));
        break;
      case MessageType.video:
        items.add(ListenItem(
          speechText: sameAsPrev
              ? l.listenSentVideo('').trim()
              : l.listenSentVideo(speaker),
        ));
        break;
      case MessageType.file:
        items.add(ListenItem(
          speechText: sameAsPrev
              ? l.listenSentFile('').trim()
              : l.listenSentFile(speaker),
        ));
        break;
      case MessageType.merged:
        final title = sanitizeTextForTts(
            (m.messagePayload as MergedMessagePayload?)?.title ?? '');
        items.add(ListenItem(
          speechText: sameAsPrev
              ? l.listenSentMerged('', title).trim()
              : l.listenSentMerged(speaker, title),
        ));
        break;
      case MessageType.audio:
        final payload = m.messagePayload as AudioMessagePayload?;
        final path = (payload?.audioPath?.isNotEmpty ?? false)
            ? payload!.audioPath!
            : (payload?.audioURL ?? '');
        items.add(ListenItem(
          // Same sender: skip the spoken prefix, just play the audio.
          //
          // 同样的发送者：跳过语音前缀，直接播放音频。
          speechText: sameAsPrev ? '' : l.listenSays(speaker),
          audioPath: path.isEmpty ? null : path,
        ));
        break;
      default:
        continue;
    }
    lastSpeakerKey = speakerKey;
  }
  return items;
}
