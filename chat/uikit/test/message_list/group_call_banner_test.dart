import 'dart:async';
import 'dart:convert';

import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/call_ui_extension.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/join_in_group_call_widget.dart';
import 'package:tuikit_atomic_x/base_component/utils/tui_event_bus.dart';

Map<String, Object?> _call({String media = 'audio'}) => {
      'business_type': 'callkit',
      'call_id': 'call-1',
      'call_media_type': media,
      'user_list': [
        {'userid': 'a'},
        {'userid': 'b'}
      ],
    };
Map<String, String> _attributes(Object? value) =>
    {'inner_attr_kit_info': jsonEncode(value)};

void main() {
  test('仅接受有真实场次和已知媒体的腾讯通话群属性', () {
    for (final media in ['audio', 'video']) {
      final parsed =
          CallUIExtension.parseGroupCallData(_attributes(_call(media: media)))!;
      expect(parsed.callId, 'call-1');
      expect(parsed.userIds, ['a', 'b']);
      expect(parsed.mediaType,
          media == 'audio' ? CallMediaType.audio : CallMediaType.video);
    }
    for (final invalid in [
      null,
      [],
      'text',
      {..._call(), 'business_type': 'room'},
      {..._call(), 'call_id': null},
      {..._call(), 'call_id': ''},
      {..._call(), 'call_id': ' call-1'},
      {..._call(), 'call_id': 12},
      {..._call(), 'call_media_type': 'other'},
      {..._call(), 'call_media_type': null},
      {..._call(), 'user_list': null},
      {..._call(), 'user_list': []},
      {
        ..._call(),
        'user_list': [
          {'userid': 'a'}
        ]
      },
      {
        ..._call(),
        'user_list': [
          {'userid': 'a'},
          {'userid': 'a'}
        ]
      },
      {
        ..._call(),
        'user_list': [
          {'userid': 'a'},
          {'userid': 12}
        ]
      },
      {
        ..._call(),
        'user_list': [
          {'userid': 'a'},
          {'userid': ' b'}
        ]
      },
      {
        ..._call(),
        'user_list': [
          {'userid': 'a'},
          'b'
        ]
      },
    ]) {
      expect(CallUIExtension.parseGroupCallData(_attributes(invalid)), isNull);
    }
    expect(CallUIExtension.parseGroupCallData(null), isNull);
    expect(
        CallUIExtension.parseGroupCallData({'inner_attr_kit_info': '{broken'}),
        isNull);
  });

  test('去重不增加横幅人数，结束清空属性后不保留加入入口', () {
    final data = CallUIExtension.parseGroupCallData(_attributes({
      ..._call(),
      'user_list': [
        {'userid': 'a'},
        {'userid': 'b'},
        {'userid': 'b'}
      ],
    }))!;
    expect(data.userIds, ['a', 'b']);
    expect(() => data.userIds.add('c'), throwsUnsupportedError);
    expect(CallUIExtension.getJoinInGroupCallWidget('group', const {}),
        isA<SizedBox>());
    expect(CallUIExtension.getJoinInGroupCallWidget('', _attributes(_call())),
        isA<SizedBox>());
  });

  testWidgets('60像素单行横幅按本端状态切换，加入与恢复传递同一真实callId', (tester) async {
    final store = _CallStore();
    final login = _LoginStore('a');
    final observer = _JoinObserver();
    TUIEventBus.shared.subscribe('call.startJoin', null, observer);
    try {
      await tester.pumpWidget(_host(JoinInGroupCallWidget(
        userIDs: const ['a', 'b'],
        mediaType: CallMediaType.audio,
        groupId: 'group',
        callId: 'call-1',
        callStore: store,
        loginStore: login,
        memberNameLoader: (_, __) async => '杨洋阳（一只羊）',
      )));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(JoinInGroupCallWidget)),
          const Size(374, 60));
      expect(find.text('杨洋阳（一只羊）等2人正在语音通话'), findsOneWidget);
      expect(find.text('立即加入'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(AppIcons.close), findsNothing);
      await tester.tap(find.text('立即加入'));
      expect(observer.calls, ['call-1']);
      expect(observer.mediaTypes, [CallMediaType.audio]);

      // 其他场次正在接通不能把当前横幅显示为已加入。
      store.state.selfInfo.value = _Participant(CallParticipantStatus.accept);
      store.state.activeCall.value = _CallInfo('other-call');
      await tester.pump();
      expect(find.text('立即加入'), findsOneWidget);
      store.state.activeCall.value = _CallInfo('call-1');
      await tester.pump();
      expect(find.text('已加入'), findsOneWidget);
      await tester.tap(find.text('已加入'));
      expect(observer.calls, ['call-1', 'call-1']);
      expect(observer.mediaTypes, [CallMediaType.audio, CallMediaType.audio]);

      // SDK 结束后可保留 activeCall，必须同时核对本端成员状态。
      store.state.selfInfo.value = _Participant(CallParticipantStatus.none);
      await tester.pump();
      expect(find.text('立即加入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      TUIEventBus.shared.unsubscribe('call.startJoin', null, observer);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      login.dispose();
    }
  });

  testWidgets('切换群场次后丢弃迟到姓名，查询失败保留真实成员标识', (tester) async {
    final store = _CallStore();
    final login = _LoginStore('a');
    final oldName = Completer<String?>();
    Future<String?> load(String group, String user) async {
      if (user == 'a') return oldName.future;
      throw StateError('无资料');
    }

    Widget banner(String callId, List<String> ids) =>
        _host(JoinInGroupCallWidget(
          userIDs: ids,
          mediaType: CallMediaType.video,
          groupId: 'group',
          callId: callId,
          callStore: store,
          loginStore: login,
          memberNameLoader: load,
        ));
    await tester.pumpWidget(banner('old', ['a', 'b']));
    login.account = 'c';
    await tester.pumpWidget(banner('new', ['c', 'd']));
    await tester.pumpAndSettle();
    oldName.complete('旧场成员');
    await tester.pumpAndSettle();
    expect(find.text('c等2人正在视频通话'), findsOneWidget);
    expect(find.textContaining('旧场成员'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    login.dispose();
  });

  testWidgets('鸿蒙群通话横幅使用群属性加入，无需 Flutter 通话状态', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.ohos;
    final login = _LoginStore('a');
    final observer = _JoinObserver();
    TUIEventBus.shared.subscribe('call.startJoin', null, observer);
    try {
      await tester.pumpWidget(_host(JoinInGroupCallWidget(
        userIDs: const ['a', 'b'],
        mediaType: CallMediaType.audio,
        groupId: 'group',
        callId: 'call-1',
        loginStore: login,
        memberNameLoader: (_, __) async => '甲',
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即加入'));
      expect(observer.calls, ['call-1']);
      login.account = 'guest';
      await tester.pump();
      expect(find.text('立即加入'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TUIEventBus.shared.unsubscribe('call.startJoin', null, observer);
      login.dispose();
    }
  });

  testWidgets('非参与者默认隐藏，当前账号同场有效状态才可恢复，退出后立即失效', (tester) async {
    final store = _CallStore();
    final login = _LoginStore('guest');
    final observer = _JoinObserver();
    TUIEventBus.shared.subscribe('call.startJoin', null, observer);
    try {
      await tester.pumpWidget(_host(JoinInGroupCallWidget(
        userIDs: const ['a', 'b'],
        mediaType: CallMediaType.audio,
        groupId: 'group',
        callId: 'call-1',
        callStore: store,
        loginStore: login,
        memberNameLoader: (_, __) async => '甲',
      )));
      await tester.pumpAndSettle();
      expect(find.text('立即加入'), findsNothing);
      store.state.activeCall.value = _CallInfo('call-1');
      store.state.selfInfo.value =
          _Participant(CallParticipantStatus.accept, id: 'guest');
      await tester.pump();
      expect(find.text('已加入'), findsOneWidget);
      final staleAction =
          tester.widget<TextButton>(find.byType(TextButton)).onPressed!;

      // 登录变化先于下一帧，旧按钮回调也必须被资格校验拦住。
      login.account = 'other-account';
      staleAction();
      await tester.pump();
      expect(observer.calls, isEmpty);
      expect(find.text('已加入'), findsNothing);
      login.account = 'guest';
      store.state.selfInfo.value =
          _Participant(CallParticipantStatus.none, id: 'guest');
      await tester.pump();
      expect(find.text('立即加入'), findsNothing);

      // 群属性确认的参与者可加入，但退出登录后不能继续显示或响应。
      login.account = 'a';
      await tester.pump();
      expect(find.text('立即加入'), findsOneWidget);
      login.account = null;
      await tester.pump();
      expect(find.text('立即加入'), findsNothing);
    } finally {
      TUIEventBus.shared.unsubscribe('call.startJoin', null, observer);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      login.dispose();
    }
  });
}

Widget _host(Widget child) => MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: Scaffold(body: Center(child: SizedBox(width: 374, child: child))),
    );

final class _CallInfo extends Fake implements CallInfo {
  _CallInfo(this.callId);
  @override
  final String callId;
}

final class _Participant extends Fake implements CallParticipantInfo {
  _Participant(this.status, {this.id = 'a'});
  @override
  final CallParticipantStatus status;
  @override
  final String id;
}

/// 固定 SDK 登录资料并允许显式模拟退出，不触发真实登录接口。
final class _LoginStore extends ChangeNotifier implements LoginStore {
  _LoginStore(this._account);

  /// 模拟当前账号；空值表示退出登录，驱动横幅权限立即失效。
  String? _account;

  /// 先切换身份再通知视图，允许测试上一帧按钮的二次权限校验。
  set account(String? value) {
    _account = value;
    notifyListeners();
  }

  @override
  LoginState get loginState => LoginState(
        loginStatus:
            _account == null ? LoginStatus.unlogin : LoginStatus.logined,
        loginUserInfo: _account == null ? null : UserProfile(userID: _account!),
      );

  @override
  dynamic noSuchMethod(Invocation call) => super.noSuchMethod(call);
}

final class _CallState extends Fake implements CallState {
  @override
  final ValueNotifier<CallInfo> activeCall =
      ValueNotifier<CallInfo>(_CallInfo(''));
  @override
  final ValueNotifier<CallParticipantInfo> selfInfo =
      ValueNotifier<CallParticipantInfo>(
          _Participant(CallParticipantStatus.none));
}

final class _CallStore extends Fake implements CallStore {
  @override
  final _CallState state = _CallState();
  void dispose() {
    state.activeCall.dispose();
    state.selfInfo.dispose();
  }
}

final class _JoinObserver implements TUIObserver {
  final calls = <String>[];
  final mediaTypes = <CallMediaType>[];
  @override
  void onNotify(String event, String? key, NotifyParams? params) {
    calls.add(params!.data!['callId'] as String);
    mediaTypes.add(params.data!['mediaType'] as CallMediaType);
  }
}
