import 'package:app_ui/app_ui.dart';
import 'package:tuikit_atomic_x/atomicx.dart';

import '../../ai/tts/tts_text_sanitizer.dart';

/// A single unit of the "listen from here" playback queue.
///
/// [speechText] is synthesized via TTS. For voice messages [audioPath] is the
/// original audio to play right after the spoken prefix; null otherwise.
class ListenItem {
  final String speechText;
  final String? audioPath;

  const ListenItem({required this.speechText, this.audioPath});
}

/// Resolve a non-self speaker's display name (remark > nameCard > nickname > id).
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
