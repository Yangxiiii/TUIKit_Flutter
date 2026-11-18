import 'dart:io';

import "package:tuikit_atomic_x/atomicx.dart";
import "package:tuikit_atomic_x/base_component/utils/tui_event_bus.dart";
import "package:tencent_calls_uikit/src/tui_call_kit_impl.dart";

/// 将聊天事件交给 Flutter 通话引擎；鸿蒙由宿主原生桥独占处理。
class EventBusHandler extends TUIObserver {
  static final EventBusHandler _instance = EventBusHandler();
  static EventBusHandler get instance => _instance;

  EventBusHandler() {
    TUIEventBus.shared.subscribe("call.startCall", null, this);
    TUIEventBus.shared.subscribe("call.startJoin", null, this);
  }

  @override
  void onNotify(String event, String? key, NotifyParams? params) {
    // 鸿蒙登录的是原生 AtomicXCore，不能把同一事件再次送到未登录的 Flutter 引擎。
    if (Platform.operatingSystem == 'ohos') return;
    if (params == null || params.data == null || params.data!.isEmpty) {
      return;
    }

    if (event == "call.startCall") {
      handleStartCall(key, params);
      return;
    }

    if (event == "call.startJoin") {
      handleStartJoin(key, params);
      return;
    }
  }

  void handleStartCall(String? key, NotifyParams? params) {
    List<String> participantIds = params?.data?["participantIds"] ?? [];
    String chatGroupId = params?.data?["chatGroupId"] ?? "";
    CallMediaType mediaType = params?.data?["mediaType"] ?? CallMediaType.audio;
    int timeout = params?.data?["timeout"] ??
        (chatGroupId.isEmpty && participantIds.length == 1 ? 45 : 30);

    CallParams callParams = CallParams();
    callParams.chatGroupId = chatGroupId;
    callParams.timeout = timeout;

    TUICallKitImpl.instance.calls(participantIds, mediaType, callParams);
  }

  void handleStartJoin(String? key, NotifyParams? params) {
    String callId = params?.data?["callId"] ?? "";
    TUICallKitImpl.instance.join(callId);
  }
}
