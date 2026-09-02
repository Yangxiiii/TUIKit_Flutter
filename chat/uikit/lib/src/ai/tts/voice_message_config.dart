import 'package:tuikit_atomic_x/atomicx.dart';

/// Minimal key-value backend used by [VoiceMessageConfig].
///
/// Abstracted so tests can inject an in-memory fake instead of the
/// SharedPreferences-backed [StorageUtil].
///
/// [VoiceMessageConfig] 使用的最小键值后端。
///
/// 抽象化以便测试可以注入内存中的假对象，而不是依赖 SharedPreferences 的 [StorageUtil]。
abstract class VoiceConfigStore {
  Future<Object?> get(String key);
  Future<bool> set<T>(String key, T value);
  Future<bool> remove(String key);
}

class _StorageUtilStore implements VoiceConfigStore {
  const _StorageUtilStore();

  @override
  Future<Object?> get(String key) => StorageUtil.get(key);

  @override
  Future<bool> set<T>(String key, T value) => StorageUtil.set<T>(key, value);

  @override
  Future<bool> remove(String key) => StorageUtil.remove(key);
}

String _currentLoginUserId() {
  try {
    return LoginStore.shared.loginState.loginUserInfo?.userID ?? '';
  } catch (_) {
    return '';
  }
}

/// Per-user persisted configuration for the chat TTS suite.
///
/// Stores the record-translation target language (independent from the global
/// message translate target) and the selected TTS voice. Keys are namespaced
/// by the current login user id, mirroring iOS `TUITextToVoiceConfig`.
///
/// 针对每个用户的聊天 TTS 套件持久化配置。
///
/// 存储记录翻译的目标语言（独立于全局消息翻译目标）和已选择的 TTS 语音。键按当前登录用户 ID 命名空间化，类似 iOS 的 `TUITextToVoiceConfig`。
class VoiceMessageConfig {
  VoiceMessageConfig({
    VoiceConfigStore? store,
    String Function()? userIdProvider,
  })  : _store = store ?? const _StorageUtilStore(),
        _userIdProvider = userIdProvider ?? _currentLoginUserId;

  /// Shared instance used by the UI layer.
  ///
  /// UI 层使用的共享实例。
  static final VoiceMessageConfig instance = VoiceMessageConfig();

  final VoiceConfigStore _store;
  final String Function() _userIdProvider;

  static const String _kRecordTranslateLang =
      'voice_record_translate_target_language';
  static const String _kSelectedVoiceId = 'voice_selected_voice_id';
  static const String _kSelectedVoiceName = 'voice_selected_voice_name';

  String _recordTranslateTargetLanguage = '';
  String _selectedVoiceId = '';
  String _selectedVoiceName = '';

  String _userKey(String base) {
    final uid = _userIdProvider();
    return uid.isEmpty ? base : '${uid}_$base';
  }

  /// Load the current user's persisted values into memory. Call after login
  /// (or user switch) before reading the synchronous getters.
  ///
  /// 将当前用户的持久化值加载到内存中。在登录（或切换用户）后、读取同步获取器之前调用。
  Future<void> load() async {
    final lang = await _store.get(_userKey(_kRecordTranslateLang));
    final voiceId = await _store.get(_userKey(_kSelectedVoiceId));
    final voiceName = await _store.get(_userKey(_kSelectedVoiceName));
    _recordTranslateTargetLanguage = lang is String ? lang : '';
    _selectedVoiceId = voiceId is String ? voiceId : '';
    _selectedVoiceName = voiceName is String ? voiceName : '';
  }

  /// Record-translation target language code (empty when never set).
  ///
  /// 记录翻译的目标语言代码（未设置时为空）。
  String get recordTranslateTargetLanguage => _recordTranslateTargetLanguage;

  /// Selected TTS voice id (empty means the built-in "default" voice).
  ///
  /// 已选择的 TTS 语音 ID（为空表示使用内置的“默认”语音）。
  String get selectedVoiceId => _selectedVoiceId;

  /// Selected TTS voice display name (empty when using the default voice).
  ///
  /// 已选择的 TTS 语音显示名称（使用默认语音时为空）。
  String get selectedVoiceName => _selectedVoiceName;

  Future<bool> setRecordTranslateTargetLanguage(String languageCode) async {
    _recordTranslateTargetLanguage = languageCode;
    return _store.set<String>(_userKey(_kRecordTranslateLang), languageCode);
  }

  Future<bool> setSelectedVoice({
    required String voiceId,
    required String name,
  }) async {
    _selectedVoiceId = voiceId;
    _selectedVoiceName = name;
    final ok1 = await _store.set<String>(_userKey(_kSelectedVoiceId), voiceId);
    final ok2 = await _store.set<String>(_userKey(_kSelectedVoiceName), name);
    return ok1 && ok2;
  }
}
