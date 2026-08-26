import 'package:app_ui/app_ui.dart';

/// A TTS voice option (built-in default voice or a user cloned custom voice).
class CustomVoiceItem {
  final String voiceId;
  final String name;
  final bool isDefault;

  const CustomVoiceItem({
    required this.voiceId,
    required this.name,
    this.isDefault = false,
  });

  @override
  bool operator ==(Object other) =>
      other is CustomVoiceItem && other.voiceId == voiceId;

  @override
  int get hashCode => voiceId.hashCode;
}

/// Voice ids of the built-in system voices, mirroring iOS
/// `TUITextToVoiceConfig.systemVoiceList`.
const String kVoiceIdXiaoxuMale = 'male-kefu-xiaoxu';
const String kVoiceIdXiaomeiFemale = 'female-kefu-xiaomei';
const String kVoiceIdXiaoxinFemale = 'female-kefu-xiaoxin';
const String kVoiceIdXiaoyueFemale = 'female-kefu-xiaoyue';

/// Built-in default voice list: the "default" entry (empty voiceId) followed by
/// the system voices. Names are resolved from [AppLocalizedText].
List<CustomVoiceItem> defaultVoiceList(AppLocalizedText l) {
  return [
    CustomVoiceItem(voiceId: '', name: l.voiceDefault, isDefault: true),
    CustomVoiceItem(
        voiceId: kVoiceIdXiaoxuMale, name: l.voiceXiaoxuMale, isDefault: true),
    CustomVoiceItem(
        voiceId: kVoiceIdXiaomeiFemale,
        name: l.voiceXiaomeiFemale,
        isDefault: true),
    CustomVoiceItem(
        voiceId: kVoiceIdXiaoxinFemale,
        name: l.voiceXiaoxinFemale,
        isDefault: true),
    CustomVoiceItem(
        voiceId: kVoiceIdXiaoyueFemale,
        name: l.voiceXiaoyueFemale,
        isDefault: true),
  ];
}
