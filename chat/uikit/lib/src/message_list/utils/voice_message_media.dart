import 'dart:io';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

/// 语音资源确实消失与暂时不可用分别处理，网络失败不能隐藏重试入口。
final class VoiceMediaFailure implements Exception {
  const VoiceMediaFailure({this.expired = false});

  /// 仅在腾讯刷新后的资源地址明确返回404或410时判定消失。
  final bool expired;
}

/// 复用腾讯下载和本地播放标记；资源探测只读取SDK返回地址，不引入业务后端。
final class VoiceMessageMedia {
  VoiceMessageMedia(
    this.message, {
    MessageActionStore? actions,
    V2TIMMessageManager? sdk,
    HttpClient Function()? clientFactory,
  })  : _actions = actions ?? MessageActionStore.create(message),
        _sdk = sdk ?? TencentImSDKPlugin.v2TIMManager.getMessageManager(),
        _clientFactory = clientFactory ?? HttpClient.new;

  /// 当前消息的SDK模型；下载后由既有SDK更新本地音频路径。
  final MessageInfo message;
  final MessageActionStore _actions;
  final V2TIMMessageManager _sdk;
  final HttpClient Function() _clientFactory;

  /// SDK异步回调期间账号可能切换，旧操作不能读取或修改新账号的同ID消息。
  final String? _userId = LoginStore.shared.loginState.loginUserInfo?.userID;
  bool get _sameAccount =>
      LoginStore.shared.loginState.loginUserInfo?.userID == _userId;

  /// localCustomInt最低位由本项目用于已播放标记，其他位及ASR自定义数据保持原样。
  static const _playedFlag = 1;

  /// 从腾讯本地消息读取标记，不读取AtomicX内部rawMessage或触发云端消息查询。
  Future<bool> wasPlayed() async =>
      (((await _localMessage())?.localCustomInt ?? 0) & _playedFlag) != 0;

  /// 原生SDK按当前登录账号读取本地消息，保留其他自定义数据及标记位。
  Future<V2TimMessage?> _localMessage() async {
    if (message.msgID.isEmpty) return null;
    final result = await _sdk.findMessages(messageIDList: [message.msgID]);
    if (result.code != 0 || !_sameAccount) return null;
    return result.data
        ?.where((item) => item.msgID == message.msgID)
        .firstOrNull;
  }

  /// 优先复用有效本地文件；下载失败时刷新地址核实资源，不把6009一律当作过期。
  Future<String> load() async {
    if (!_sameAccount) throw const VoiceMediaFailure();
    final cached = _localPath();
    if (cached != null) return cached;
    if (message.msgID.isEmpty) throw const VoiceMediaFailure();
    final result = await _actions.downloadMedia();
    if (!_sameAccount) throw const VoiceMediaFailure();
    final downloaded = _localPath();
    if (result.isSuccess && downloaded != null) return downloaded;
    // 腾讯6009同时涵盖网络失败和文件过期，只有资源地址的明确响应才能关闭重试入口。
    final missing = (result.isSuccess ||
            result.errorCode == 6009 ||
            result.errorCode == 6010) &&
        await _resourceMissing();
    throw VoiceMediaFailure(expired: missing);
  }

  /// 空文件不是可播放缓存，仍需走SDK下载或资源核实。
  String? _localPath() {
    final payload = message.messagePayload;
    final path = payload is AudioMessagePayload ? payload.audioPath : null;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() && file.lengthSync() > 0 ? path : null;
  }

  /// 先从腾讯取得当前签名地址，再做HEAD检查；权限、超时或其他状态都保留重试。
  Future<bool> _resourceMissing() async {
    HttpClient? client;
    try {
      final fresh = await _sdk
          .getMessageOnlineUrl(msgID: message.msgID)
          .timeout(const Duration(seconds: 5));
      if (fresh.code != 0 || !_sameAccount) return false;
      final uri = Uri.tryParse(fresh.data?.soundElem?.url ?? '');
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty) {
        return false;
      }
      client = _clientFactory()..connectionTimeout = const Duration(seconds: 5);
      final request =
          await client.headUrl(uri).timeout(const Duration(seconds: 5));
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      return response.statusCode == HttpStatus.notFound ||
          response.statusCode == HttpStatus.gone;
    } catch (_) {
      // 无法验证资源时不能假报过期，下载或播放入口应继续可重试。
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  /// 设置消息自定义数据，可以用来标记语音、视频消息是否已经播放（本地保存，不会发送到对端，程序卸载重装后失效）。
  Future<void> markPlayed() async {
    final raw = await _localMessage();
    if (raw == null || ((raw.localCustomInt ?? 0) & _playedFlag) != 0) return;
    final updated = (raw.localCustomInt ?? 0) | _playedFlag;
    final result =
        await _sdk.setLocalCustomInt(message: raw, localCustomInt: updated);
    if (result.code == 0) raw.localCustomInt = updated;
  }
}
