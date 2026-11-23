import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/services.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:tuikit_atomic_x/base_component/utils/tui_event_bus.dart';

import '../../state/group_call_metadata.dart';

/// 管理鸿蒙原生通话登录及呼叫入口，兼容由宿主独立管理 Flutter 聊天的模式。
final class HarmonyCallBridge implements TUIObserver {
  HarmonyCallBridge(
    this._logger, {
    required ActionGuard guard,
    LoginStore? chatLoginStore,
    MethodChannel channel = const MethodChannel('tencent_calls_uikit'),
  }) : _guard = guard,
       _chatLoginStore = chatLoginStore ?? LoginStore.shared,
       _channel = channel;

  final AppLogger _logger;

  /// 与鸿蒙插件共用方法名和参数格式；媒体采集与渲染在原生侧。
  final MethodChannel _channel;

  /// 聊天和原生通话使用两个 Store，登录代次须一致。
  final LoginStore _chatLoginStore;

  /// 聊天事件与宿主多人入口共用同一个原生准入过程。
  final ActionGuard _guard;

  /// 原生成功发起多人通话后，由当前宿主会话发布通话起始消息。
  GroupCallStartedHandler? onGroupCallStarted;

  /// 仅当前成功登录代次可接收聊天呼叫事件。
  bool _subscribed = false;

  /// 原生登录所属账号；登出后不允许迟到的选人结果发起呼叫。
  String? _accountId;

  /// 登录和登出共同递增，迟到的原生登录不能恢复旧账号或订阅。
  int _sessionEpoch = 0;

  /// 串行原生会话操作，保证登出发生在已经开始的登录完成后，避免原生状态逆序。
  Future<void> _sessionChanges = Future<void>.value();

  /// 同步原生通话并开放呼叫入口；宿主已管理聊天时仅操作原生 Store。
  Future<CompletionHandler> login({
    required int sdkAppId,
    required String userId,
    required String userSig,
    bool includeChat = true,
  }) async {
    final epoch = ++_sessionEpoch;
    _clearLoginState();
    final operation = _sessionChanges.then((_) async {
      // 等待旧操作结束后只处理最新代次，避免过期凭证登录原生。
      _checkSession(epoch);
      if (includeChat) {
        final chatResult = await _chatLoginStore.login(
          sdkAppID: sdkAppId,
          userID: userId,
          userSig: userSig,
        );
        _checkSession(epoch);
        if (!chatResult.isSuccess) return chatResult;
      }
      try {
        await _channel.invokeMethod<void>('harmonyLogin', {
          'sdkAppId': sdkAppId,
          'userId': userId,
          'userSig': userSig,
        });
      } catch (_) {
        // 原生登录失败时回收本次聊天登录；已有新操作排队时由新操作接管。
        if (includeChat && epoch == _sessionEpoch) {
          try {
            await _logoutChat();
          } catch (error, stack) {
            _logger.error('鸿蒙通话登录失败后的聊天登出失败', error: error, stackTrace: stack);
          }
        }
        rethrow;
      }
      // 两侧均已就绪才开放入口，迟到的结果不能恢复旧账号订阅。
      _checkSession(epoch);
      _accountId = userId;
      TUIEventBus.shared.subscribe('call.startCall', null, this);
      TUIEventBus.shared.subscribe('call.startJoin', null, this);
      _subscribed = true;
      return CompletionHandler();
    });
    // 当前调用保留失败结果，队尾吸收失败仅为了让后续登出或新登录仍可执行。
    _sessionChanges = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// 撤销呼叫入口并清理原生会话，按登录模式决定是否退出 Flutter 聊天。
  Future<void> logout({bool includeChat = true}) async {
    ++_sessionEpoch;
    _clearLoginState();
    final operation = _sessionChanges.then((_) async {
      // 联合登录模式下，即使原生登出失败也要退出由桥管理的聊天。
      try {
        await _channel.invokeMethod<void>('harmonyLogout');
      } finally {
        if (includeChat) await _logoutChat();
      }
    });
    _sessionChanges = operation.catchError((Object _) {});
    await operation;
  }

  /// 保留 Flutter 聊天登出的真实错误，供宿主会话清理感知。
  Future<void> _logoutChat() async {
    final result = await _chatLoginStore.logout();
    if (!result.isSuccess) {
      throw StateError(
        '腾讯云 IM 登出失败：${result.errorCode} ${result.errorMessage}',
      );
    }
  }

  /// 拒绝上一账号或上一次登录代次迟到的操作结果。
  void _checkSession(int epoch) {
    if (epoch != _sessionEpoch) throw StateError('通话登录状态已变更');
  }

  /// 立即禁止业务呼叫并解除订阅，不等待原生登录或登出的异步返回。
  void _clearLoginState() {
    _accountId = null;
    if (_subscribed) {
      TUIEventBus.shared.unsubscribe('call.startCall', null, this);
      TUIEventBus.shared.unsubscribe('call.startJoin', null, this);
      _subscribed = false;
    }
  }

  /// 直接呼叫返回真实平台结果；群标识和邀请时限传给同一原生 CallKit。
  Future<void> calls(
    List<String> userIds,
    CallMediaType mediaType, [
    CallParams? params,
  ]) => _guard.singleFlight(
    'tim.call.admission',
    () => _calls(userIds, mediaType, params ?? CallParams()),
  );

  /// 去重后提交平台参数，真实错误交还调用方，不在事件桥伪造成功。
  Future<void> _calls(
    List<String> userIds,
    CallMediaType mediaType,
    CallParams params,
  ) async {
    final account = _accountId;
    final epoch = _sessionEpoch;
    // SDK 去重后最多容纳八位受邀者和主叫，不能把本人计入受邀名单。
    final ids = List<String>.unmodifiable(userIds.toSet());
    if (account == null) throw StateError('通话未登录');
    if (ids.isEmpty ||
        ids.length > 8 ||
        ids.any(
          (id) => id.trim().isEmpty || id != id.trim() || id == account,
        )) {
      throw ArgumentError('通话成员无效');
    }
    final groupId = params.chatGroupId;
    final userData = params.userData;
    final onStarted = onGroupCallStarted;
    // 有真实群标识时，即使只选中一人也仍然是群呼。
    final isTemporaryMulti = GroupCallMetadata.isTemporaryMulti(userData);
    final isGroup = groupId.isNotEmpty || ids.length > 1 || isTemporaryMulti;
    final attemptId = onStarted != null && isGroup
        ? GroupCallMetadata.newAttemptId()
        : null;
    // 仅追加到通话组件拥有的元数据，其他调用方的透传内容须原样保存。
    final outgoingUserData =
        attemptId != null && (userData.isEmpty || isTemporaryMulti)
        ? GroupCallMetadata.withAttempt(userData, attemptId)
        : userData;
    // 权限弹窗可能跨越账号切换；原生二次校验后，Flutter 还要校验发布消息的代次。
    await _channel.invokeMethod<void>('harmonyCalls', {
      'userIds': ids,
      'mediaType': mediaType == CallMediaType.video ? 'video' : 'audio',
      'chatGroupId': groupId,
      'timeout': 45,
      'roomId': params.roomId,
      'userData': outgoingUserData,
      'isEphemeralCall': params.isEphemeralCall,
      'cloudRecordPolicy': params.cloudRecordPolicy.name,
      'offlinePushTitle': params.offlinePushTitle,
      'offlinePushDescription': params.offlinePushDescription,
    });
    _checkSession(epoch);
    if (attemptId != null && onStarted != null) {
      // SDK 接受呼叫后才发群消息，消息发送失败不改变本次通话结果。
      unawaited(
        Future.sync(
          () => onStarted(groupId, account, mediaType, ids, attemptId),
        ).catchError((Object error, StackTrace stack) {
          _logger.error('群通话发起消息发送失败', error: error, stackTrace: stack);
        }),
      );
    }
  }

  /// 加入真实场次或恢复同场原生窗口；与新呼叫共用准入，失败交还调用方。
  Future<void> join(String callId, CallMediaType? mediaType) =>
      _guard.singleFlight('tim.call.admission', () async {
        if (_accountId == null) throw StateError('通话未登录');
        if (callId.isEmpty || callId != callId.trim()) {
          throw ArgumentError('通话场次无效');
        }
        final epoch = _sessionEpoch;
        // 媒体类型来自腾讯群属性，仅用于权限；入会资格和场次容量由 SDK 校验。
        await _channel.invokeMethod<void>('harmonyJoin', {
          'callId': callId,
          if (mediaType != null)
            'mediaType': mediaType == CallMediaType.video ? 'video' : 'audio',
        });
        _checkSession(epoch);
      });

  /// 事件没有 Future 返回通道，因此在受保护过程内提示一次平台失败。
  Future<void> _joinFromEvent(String callId, CallMediaType mediaType) =>
      _guard.singleFlight(('tim.call.join.event', callId), () async {
        final epoch = _sessionEpoch;
        try {
          await join(callId, mediaType);
        } catch (error, stackTrace) {
          _logger.error(
            'HarmonyOS 加入通话失败',
            error: error,
            stackTrace: stackTrace,
          );
          // 退出账号后旧场次结果只记录，不在新账号页面展示迟到提示。
          if (epoch == _sessionEpoch && _accountId != null) {
            AppToast.show('加入通话失败，请稍后重试');
          }
        }
      });

  @override
  void onNotify(String event, String? key, NotifyParams? params) {
    final data = params?.data;
    if (event == 'call.startJoin') {
      final callId = data?['callId'];
      final mediaType = data?['mediaType'];
      if (callId is! String || mediaType is! CallMediaType) {
        _logger.error('HarmonyOS 加入通话参数不完整');
        return;
      }
      unawaited(_joinFromEvent(callId, mediaType));
      return;
    }
    if (event != 'call.startCall') return;
    final participants = data?['participantIds'];
    final mediaType = data?['mediaType'];
    final groupId = data?['chatGroupId'];
    if (participants is! List ||
        participants.isEmpty ||
        participants.any((id) => id is! String) ||
        mediaType is! CallMediaType ||
        (groupId != null && groupId is! String)) {
      _logger.error('HarmonyOS 呼叫参数不完整');
      return;
    }

    // 原生 TUICallKit 自行处理权限、呼叫状态以及通话页面展示。
    unawaited(
      calls(
        participants.cast<String>(),
        mediaType,
        CallParams(chatGroupId: groupId is String ? groupId : ''),
      ).catchError((Object error, StackTrace stackTrace) {
        _logger.error('HarmonyOS 发起通话失败', error: error, stackTrace: stackTrace);
      }),
    );
  }
}
