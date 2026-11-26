import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tencent_calls_uikit/src/common/utils/logger.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tencent_calls_uikit/src/common/utils/preference.dart';
import 'package:tencent_rtc_sdk/trtc_cloud.dart';
import 'package:tencent_rtc_sdk/tx_audio_effect_manager.dart';
import 'package:tencent_calls_uikit/src/common/platform/call_kit_platform_interface.dart';

/// 依据本机通话状态控制铃声和振动，停止时作废尚在准备的铃声。
class CallingBellFeature {
  static CallingBellFeature instance = CallingBellFeature._();

  static const String _keyRingPath = "key_ring_path";
  static const String _packagePrefix = "packages/";
  static const String _pluginName = "tencent_calls_uikit/";
  static const String _assetsPrefix = "assets/audios/";
  static const String _callerRingName = "phone_dialing.mp3";
  static const String _calledRingName = "phone_ringing.mp3";
  static const int _musicId = 1;
  static const int _loopCount = 6;
  static const int _volume = 100;

  FileSystem fileSystem = const LocalFileSystem();
  bool isPlaying = false;
  bool isVibrating = false;

  VoidCallback? _selfInfoListener;
  bool _initialized = false;

  /// 用于区分异步准备中的铃声，防止上一通结束后开始响铃。
  int _ringGeneration = 0;

  CallingBellFeature._();

  void init() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _selfInfoListener = _onSelfInfoChanged;
    CallStore.shared.state.selfInfo.addListener(_selfInfoListener!);
  }

  void dispose() {
    if (!_initialized) {
      return;
    }
    if (_selfInfoListener != null) {
      CallStore.shared.state.selfInfo.removeListener(_selfInfoListener!);
      _selfInfoListener = null;
    }
    _initialized = false;
    _stopRing();
  }

  void _onSelfInfoChanged() {
    final activeCall = CallStore.shared.state.activeCall.value;
    if (activeCall.mediaType == null) {
      _stopRing();
      return;
    }

    final status = CallStore.shared.state.selfInfo.value.status;
    if (status == CallParticipantStatus.waiting) {
      _startRing();
    } else {
      _stopRing();
    }
  }

  /// 等铃声文件就绪后仅启动当前场次仍有效的提示。
  Future<void> _startRing() async {
    if (isPlaying) {
      return;
    }

    Logger.info('CallingBellFeature startRing');
    isPlaying = true;
    final generation = ++_ringGeneration;

    final filePath = await _getRingFilePath();
    if (generation != _ringGeneration) return;
    if (filePath.isEmpty) {
      isPlaying = false;
      return;
    }

    _playByTRTC(filePath, generation);

    if (_isCalled()) {
      TUICallKitPlatform.instance.startVibration();
      isVibrating = true;
    }
  }

  /// 先作废未完成的准备，再停止当前的铃声与振动。
  Future<void> _stopRing() async {
    if (!isPlaying) {
      return;
    }

    Logger.info('CallingBellFeature stopRing');
    isPlaying = false;
    _ringGeneration++;

    _stopByTRTC();

    if (isVibrating) {
      TUICallKitPlatform.instance.stopVibration();
      isVibrating = false;
    }
  }

  Future<String> _getRingFilePath() async {
    if (_isCalled()) {
      if (GlobalState.instance.enableMuteMode) {
        return "";
      }

      final customAssetName = GlobalState.instance.callingBellAssetName;
      if (customAssetName != null && customAssetName.isNotEmpty) {
        return await getAssetsFilePath(customAssetName);
      }

      final customFilePath = await PreferenceUtils.getInstance().getString(
        _keyRingPath,
      );
      if (customFilePath.isNotEmpty) {
        return customFilePath;
      }

      return await _getAssetsFilePath(_calledRingName);
    } else {
      return await _getAssetsFilePath(_callerRingName);
    }
  }

  bool _isCalled() {
    final userId = CallStore.shared.state.selfInfo.value.id;
    final inviterId = CallStore.shared.state.activeCall.value.inviterId;
    return userId != inviterId;
  }

  Future<String> getAssetsFilePath(String assetName) async {
    if (assetName.isEmpty) {
      return "";
    }

    final tempDirectory = await getTempDirectory();
    final filePath = "$tempDirectory/$assetName";
    final file = fileSystem.file(filePath);

    if (!await file.exists()) {
      final byteData = await loadAsset(assetName);
      await file.create(recursive: true);
      await file.writeAsBytes(byteData.buffer.asUint8List());
    }

    return file.path;
  }

  Future<String> _getAssetsFilePath(String ringName) async {
    final assetPath = '$_packagePrefix$_pluginName$_assetsPrefix$ringName';
    return await getAssetsFilePath(assetPath);
  }

  /// SDK 音频实例异步就绪时再次校验，避免刚结束的来电重新响铃。
  Future<void> _playByTRTC(String filePath, int generation) async {
    final trtcCloud = await TRTCCloud.sharedInstance();
    if (generation != _ringGeneration) return;
    final audioEffectManager = trtcCloud.getAudioEffectManager();

    final param = AudioMusicParam(
      id: _musicId,
      path: filePath,
      loopCount: _loopCount,
    );
    param.publish = false;
    audioEffectManager.startPlayMusic(param);
    audioEffectManager.setMusicPlayoutVolume(_musicId, _volume);
  }

  Future<void> _stopByTRTC() async {
    final trtcCloud = await TRTCCloud.sharedInstance();
    final audioEffectManager = trtcCloud.getAudioEffectManager();
    audioEffectManager.stopPlayMusic(_musicId);
  }

  @visibleForTesting
  Future<ByteData> loadAsset(String path) => rootBundle.load(path);

  @visibleForTesting
  Future<String> getTempDirectory() async =>
      (await getTemporaryDirectory()).path;
}
