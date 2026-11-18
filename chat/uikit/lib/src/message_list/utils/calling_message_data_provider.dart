import 'package:app_ui/app_ui.dart';
import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/cupertino.dart';
import 'package:app_api/app_api_models.dart';

import 'group_call_record_message.dart';

enum CallProtocolType {
  unknown,
  send,
  accept,
  reject,
  cancel,
  hangup,
  timeout,
  lineBusy,
  switchToAudio,
  switchToAudioConfirm
}

enum CallStreamMediaType { unknown, audio, video }

enum CallParticipantType { unknown, c2c, group }

enum CallParticipantRole { unknown, caller, callee }

enum CallMessageDirection { incoming, outcoming }

/// 解析腾讯通话信令与 OA 通话消息，为聊天气泡、会话摘要及历史过滤提供展示信息。
class CallingMessageDataProvider {
  bool _isExcludedFromLastMessage = false;
  bool _isExcludedFromUnreadCount = false;
  Map<String, dynamic> _jsonData = {};
  String _groupID = '';
  List<dynamic> _inviteeList = [];
  int _actionType = 0;

  CallProtocolType _protocolType = CallProtocolType.unknown;
  CallStreamMediaType _streamMediaType = CallStreamMediaType.unknown;
  CallParticipantType _participantType = CallParticipantType.unknown;
  CallParticipantRole _participantRole = CallParticipantRole.unknown;
  CallMessageDirection _direction = CallMessageDirection.outcoming;
  bool _excludeFromHistory = false;
  String _callerId = '';
  String _content = '';
  bool _isCallingSignal = false;

  /// 自有终态报告有完整多人身份；不能把两人临时通话误识别为普通单聊。
  GroupCallRecordData? _personalRecord;

  /// 已核对发起人、会话及受邀范围的业务发起消息。
  GroupCallStartData? _callStart;

  CallProtocolType get protocolType => _protocolType;

  // 媒体类型
  CallStreamMediaType get streamMediaType => _streamMediaType;

  // 通话类型
  CallParticipantType get participantType => _participantType;

  // 用户角色
  CallParticipantRole get participantRole => _participantRole;

  // 上屏信息的方向信息
  CallMessageDirection get direction => _direction;

  /// 单聊通话气泡是否展示在己方一侧，其他消息没有通话展示方向。
  bool? get isOutgoingC2c =>
      isCallingSignal && participantType == CallParticipantType.c2c
          ? direction == CallMessageDirection.outcoming
          : null;

  /// 群个人结果也使用普通气泡，方向跟随发起人而非报告消息的真实发送端。
  bool? get isOutgoingCall => _personalRecord != null
      ? direction == CallMessageDirection.outcoming
      : isOutgoingC2c;

  /// 经发送身份与会话校验的个人报告，展示资料不能作为权限依据。
  GroupCallRecordData? get personalRecord => _personalRecord;

  /// 群发起通知和临时多人发起通知按实际发送者显示左右气泡。
  bool get isCallStart => _callStart != null;

  /// 只有发起气泡随同场的 SDK 实时接通状态更新。
  String? get attemptId => _callStart?.attemptId;

  // 是否需要上屏
  bool get excludeFromHistory => _excludeFromHistory;

  // 主角ID
  String get callerId => _callerId;

  // 上屏内容
  String get content => _content;

  // 是否Call信令
  bool get isCallingSignal => _isCallingSignal;

  /// 腾讯历史载荷明确包含多位受邀者时，禁止将多人记录当作单聊回拨。
  /// 两人临时场次的 userData 不进入历史记录，不能据此虚构多人身份。
  bool get isTemporaryMultiParty =>
      isCallingSignal &&
      _groupID.isEmpty &&
      (_personalRecord != null || isCallStart || _inviteeList.toSet().length > 1);

  late MessageInfo messageInfo;
  late AppLocalizedText atomicLocale;

  CallingMessageDataProvider._(this.messageInfo);

  /// 识别腾讯群通话信令，聊天记录由独立的 OA 发起及结果消息承载。
  static bool isSdkGroupCallSignal(MessageInfo message) {
    if (message.messagePayload is! CustomMessagePayload) return false;
    final signal = CallingMessageDataProvider._(message);
    return signal._readSignalEnvelope() && signal._isSdkGroupCallSignal;
  }

  /// 仅在解析腾讯信令的分支中使用，OA 通话消息单独校验展示范围。
  bool get _isSdkGroupCallSignal => _isCallingSignal && _groupID.isNotEmpty;

  CallingMessageDataProvider(this.messageInfo, BuildContext context,
      {String? viewerId}) {
    atomicLocale = AppLocalization.of(context);
    final account =
        viewerId ?? LoginStore.shared.loginState.loginUserInfo?.userID ?? '';
    final payload = messageInfo.messagePayload;
    if (payload is CustomMessagePayload &&
        GroupCallStartData.isStart(payload.customData)) {
      _readCallStart(account);
      return;
    }
    if (GroupCallRecordMessage.isMessage(messageInfo)) {
      _isCallingSignal = true;
      final record = GroupCallRecordMessage.fromMessage(messageInfo, account);
      if (record == null) {
        _excludeFromHistory = true;
        return;
      }
      _personalRecord = record;
      _groupID = record.groupId;
      _callerId = record.callerId;
      _streamMediaType = record.mediaType == 'video'
          ? CallStreamMediaType.video
          : CallStreamMediaType.audio;
      _participantType = _groupID.isEmpty
          ? CallParticipantType.c2c
          : CallParticipantType.group;
      _participantRole = account == record.callerId
          ? CallParticipantRole.caller
          : CallParticipantRole.callee;
      _setDirection();
      _protocolType = switch (record.outcome) {
        GroupCallRecordOutcome.cancelled => CallProtocolType.cancel,
        GroupCallRecordOutcome.unanswered => CallProtocolType.timeout,
        GroupCallRecordOutcome.rejected => CallProtocolType.reject,
        GroupCallRecordOutcome.busy => CallProtocolType.lineBusy,
        GroupCallRecordOutcome.otherDeviceAccepted => CallProtocolType.accept,
        GroupCallRecordOutcome.completed ||
        GroupCallRecordOutcome.interrupted =>
          CallProtocolType.hangup,
      };
      _content = GroupCallRecordMessage.content(record, account);
      return;
    }
    _isExcludedFromLastMessage =
        messageInfo.rawMessage?.isExcludedFromLastMessage ?? false;
    _isExcludedFromUnreadCount =
        messageInfo.rawMessage?.isExcludedFromUnreadCount ?? false;

    if (!_readSignalEnvelope()) return;
    _setStreamMediaType();
    _setParticipantType();
    _setCallerId();
    _setParticipantRole();
    _setDirection();
    _setExcludeFromHistory();
    _setContent();
  }

  /// 以实际会话和发起人校验展示范围，原始载荷不提供入会入口。
  void _readCallStart(String account) {
    _isCallingSignal = true;
    final start = GroupCallRecordMessage.startFromMessage(messageInfo, account);
    if (start == null) {
      _excludeFromHistory = true;
      return;
    }
    _callStart = start;
    _groupID = start.groupId;
    _callerId = start.callerId;
    _participantType = start.groupId.isEmpty
        ? CallParticipantType.c2c
        : CallParticipantType.group;
    _participantRole = account == start.callerId
        ? CallParticipantRole.caller
        : CallParticipantRole.callee;
    _setDirection();
    _protocolType = CallProtocolType.send;
    _streamMediaType = start.mediaType == 'video'
        ? CallStreamMediaType.video
        : CallStreamMediaType.audio;
    _content = atomicLocale.startCall;
  }

  /// 从在线和离线共用的自定义载荷识别信令动作，供列表过滤与气泡展示使用。
  bool _readSignalEnvelope() {
    final payload = messageInfo.messagePayload;
    final raw = payload is CustomMessagePayload ? payload.customData : null;
    // 腾讯信令的内层 data 可能是 JSON 字符串，容器异常时按普通消息处理。
    try {
      if (raw == null || raw.isEmpty) return false;
      final outer = jsonDecode(raw);
      if (outer is! Map<String, dynamic>) return false;
      final inner = outer['data'];
      final decoded = inner is String ? jsonDecode(inner) : inner;
      if (decoded is! Map<String, dynamic>) return false;
      _jsonData = decoded;
      _groupID = outer['groupID'] is String ? outer['groupID'] as String : '';
      _inviteeList = outer['inviteeList'] is List
          ? (outer['inviteeList'] as List).whereType<String>().toList()
          : [];
      _actionType = outer['actionType'] is int ? outer['actionType'] as int : 0;
      if (_jsonData['data'] != null &&
          _jsonData['data'] is! Map<String, dynamic>) {
        return false;
      }
    } on FormatException {
      return false;
    }

    _setIsCallingSignal();
    _setProtocolType();
    return true;
  }

  _setIsCallingSignal() {
    final businessID = _jsonData['businessID'];
    if (businessID != null &&
        (businessID == 'av_call' || businessID == 'rtc_call')) {
      _isCallingSignal = true;
    } else {
      _isCallingSignal = false;
    }
  }

  _setProtocolType() {
    switch (_actionType) {
      case 1:
        final data = _jsonData['data'];
        if (data != null) {
          final cmd = data['cmd'];
          if (cmd != null) {
            if (cmd == 'switchToAudio') {
              _protocolType = CallProtocolType.switchToAudio;
            } else if (cmd == 'hangup') {
              _protocolType = CallProtocolType.hangup;
            } else if (cmd == 'videoCall') {
              _protocolType = CallProtocolType.send;
            } else if (cmd == 'audioCall') {
              _protocolType = CallProtocolType.send;
            } else {
              _protocolType = CallProtocolType.unknown;
            }
          } else {
            _protocolType = CallProtocolType.unknown;
          }
        } else {
          final callEnd = _jsonData['call_end'];
          if (callEnd != null) {
            _protocolType = CallProtocolType.hangup;
          } else {
            _protocolType = CallProtocolType.send;
          }
        }
        break;
      case 2:
        _protocolType = CallProtocolType.cancel;
        break;
      case 3:
        final data = _jsonData['data'];
        if (data != null) {
          final cmd = data['cmd'];
          if (cmd != null) {
            if (cmd == 'switchToAudio') {
              _protocolType = CallProtocolType.switchToAudioConfirm;
            } else {
              _protocolType = CallProtocolType.accept;
            }
          } else {
            _protocolType = CallProtocolType.accept;
          }
        } else {
          _protocolType = CallProtocolType.accept;
        }
        break;
      case 4:
        if (_jsonData['line_busy'] != null) {
          _protocolType = CallProtocolType.lineBusy;
        } else {
          _protocolType = CallProtocolType.reject;
        }
        break;
      case 5:
        _protocolType = CallProtocolType.timeout;
        break;
      default:
        _protocolType = CallProtocolType.unknown;
        break;
    }
  }

  _setStreamMediaType() {
    _streamMediaType = CallStreamMediaType.unknown;
    if (_protocolType == CallProtocolType.unknown) {
      _streamMediaType = CallStreamMediaType.unknown;
      return;
    }

    final callType = _jsonData['call_type'];
    if (callType != null) {
      if (callType == 1) {
        _streamMediaType = CallStreamMediaType.audio;
      } else if (callType == 2) {
        _streamMediaType = CallStreamMediaType.video;
      }
    }

    if (_protocolType == CallProtocolType.send) {
      final data = _jsonData['data'];
      if (data != null) {
        final cmd = data['cmd'];
        if (cmd != null) {
          if (cmd == 'audioCall') {
            _streamMediaType = CallStreamMediaType.audio;
          } else if (cmd == 'videoCall') {
            _streamMediaType = CallStreamMediaType.video;
          }
        }
      }
    } else if (_protocolType == CallProtocolType.switchToAudio ||
        _protocolType == CallProtocolType.switchToAudioConfirm) {
      _streamMediaType = CallStreamMediaType.video;
    }
  }

  _setParticipantType() {
    if (_protocolType == CallProtocolType.unknown) {
      _participantType = CallParticipantType.unknown;
      return;
    }

    if (_groupID.isNotEmpty) {
      _participantType = CallParticipantType.group;
    } else {
      _participantType = CallParticipantType.c2c;
    }
  }

  void _setCallerId() {
    if (_protocolType == CallProtocolType.unknown) {
      return;
    }

    final data = _jsonData['data'];
    if (data != null) {
      final inviter = data['inviter'];
      if (inviter is String) {
        _callerId = inviter;
      }
    }

    if (_callerId.isEmpty) {
      // 缺少发起人时不可把当前查看者当作发起人，避免群全员获得记录可见资格。
      _callerId = _groupID.isEmpty
          ? LoginStore.shared.loginState.loginUserInfo?.userID ?? ''
          : _protocolType == CallProtocolType.send
              ? messageInfo.from.userID
              : '';
    }
  }

  void _setParticipantRole() {
    final loginUserId = LoginStore.shared.loginState.loginUserInfo?.userID;

    if (_callerId == loginUserId) {
      _participantRole = CallParticipantRole.caller;
    } else {
      _participantRole = CallParticipantRole.callee;
    }
  }

  _setDirection() {
    if (_participantRole == CallParticipantRole.caller) {
      _direction = CallMessageDirection.outcoming;
    } else {
      _direction = CallMessageDirection.incoming;
    }
  }

  /// 群通话信令不生成会话摘要或独立消息项，单聊仍按 SDK 标志判断。
  void _setExcludeFromHistory() {
    _excludeFromHistory = _isSdkGroupCallSignal ||
        (_protocolType != CallProtocolType.unknown &&
            _isExcludedFromLastMessage &&
            _isExcludedFromUnreadCount);
  }

  _setContent() {
    if (_excludeFromHistory) {
      _content = '';
      return;
    }

    bool isCaller = _participantRole == CallParticipantRole.caller;

    if (_participantType == CallParticipantType.c2c) {
      if (_protocolType == CallProtocolType.reject) {
        _content = isCaller
            ? atomicLocale.callRejectCaller
            : atomicLocale.callRejectCallee;
      } else if (_protocolType == CallProtocolType.cancel) {
        _content = isCaller
            ? atomicLocale.callCancelCaller
            : atomicLocale.callCancelCallee;
      } else if (_protocolType == CallProtocolType.hangup) {
        final duration = _jsonData['call_end'];
        _content = duration is num && duration >= 0
            ? '${atomicLocale.stopCallTip} ${_getShowTime(duration.toInt())}'
            : atomicLocale.callEndedTheCall;
      } else if (_protocolType == CallProtocolType.timeout) {
        _content = isCaller
            ? atomicLocale.callTimeoutCaller
            : atomicLocale.callTimeoutCallee;
      } else if (_protocolType == CallProtocolType.lineBusy) {
        _content = isCaller
            ? atomicLocale.callLineBusyCaller
            : atomicLocale.callLineBusyCallee;
      } else if (_protocolType == CallProtocolType.send) {
        _content = atomicLocale.startCall;
      } else if (_protocolType == CallProtocolType.accept) {
        _content = atomicLocale.acceptCall;
      } else if (_protocolType == CallProtocolType.switchToAudio) {
        _content = atomicLocale.callingSwitchToAudio;
      } else if (_protocolType == CallProtocolType.switchToAudioConfirm) {
        _content = atomicLocale.callingSwitchToAudioAccept;
      } else {
        _content = atomicLocale.unknownCall;
      }
    } else {
      _content = atomicLocale.unknownCall;
    }
  }

  _twoDigits(int n) {
    if (n >= 10) return "$n";
    return "0$n";
  }

  _getShowTime(int seconds) {
    int secondsShow = seconds % 60;
    int minutesShow = seconds ~/ 60;
    return "${_twoDigits(minutesShow)}:${_twoDigits(secondsShow)}";
  }
}
