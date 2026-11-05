import 'dart:io';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/voice_message_media.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_online_url.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_sound_elem.dart';

class _Actions implements MessageActionStore {
  int calls = 0;
  int code = 6009;
  @override
  Future<CompletionHandler> downloadMedia({MediaQuality? quality}) async {
    calls++;
    return CompletionHandler()..errorCode = code;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sdk implements V2TIMMessageManager {
  final raw = V2TimMessage.fromJson({
    'message_risk_type_identified': 0,
    'message_msg_id': 'voice',
    'message_custom_int': 4,
    'message_custom_str': '{"voice_to_text":"已有识别"}'
  });
  int writes = 0;
  int code = 0;
  int urlReads = 0;
  @override
  Future<V2TimValueCallback<List<V2TimMessage>>> findMessages(
          {required List<String> messageIDList}) async =>
      V2TimValueCallback(code: code, desc: '', data: [raw]);
  @override
  Future<V2TimCallback> setLocalCustomInt(
      {V2TimMessage? message,
      String? msgID,
      required int localCustomInt}) async {
    writes++;
    expect(identical(message, raw), isTrue);
    expect(localCustomInt, 5);
    return V2TimCallback(code: code, desc: '');
  }

  @override
  Future<V2TimValueCallback<V2TimMessageOnlineUrl>> getMessageOnlineUrl(
      {V2TimMessage? message, String? msgID}) async {
    urlReads++;
    return V2TimValueCallback(
        code: 0,
        desc: '',
        data: V2TimMessageOnlineUrl(
            soundElem: V2TimSoundElem(url: 'https://tencent.invalid/audio')));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.status);
  final int status;
  bool closed = false;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> headUrl(Uri url) async => _Request(status);
  @override
  void close({bool force = false}) => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.status);
  final int status;
  @override
  Future<HttpClientResponse> close() async => _Response(status);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response implements HttpClientResponse {
  _Response(this.statusCode);
  @override
  final int statusCode;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MessageInfo message([String? path]) => MessageInfo(
      msgID: 'voice',
      messageType: MessageType.audio,
      messagePayload: AudioMessagePayload(audioPath: path, audioDuration: 2));

  test('有效本地缓存直接播放，空文件仍从腾讯下载', () async {
    final directory = Directory.systemTemp.createTempSync('voice-media-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/audio.m4a')..writeAsStringSync('AAC');
    final actions = _Actions();
    final sdk = _Sdk();
    expect(
        await VoiceMessageMedia(message(file.path), actions: actions, sdk: sdk)
            .load(),
        file.path);
    expect(actions.calls, 0);
    file.writeAsStringSync('');
    await expectLater(
        VoiceMessageMedia(message(file.path),
            actions: actions,
            sdk: sdk,
            clientFactory: () => _Client(503)).load(),
        throwsA(isA<VoiceMediaFailure>()
            .having((e) => e.expired, 'expired', false)));
    expect(actions.calls, 1);
  });

  test('6009必须核实404或410，权限与暂时网络失败仍可重试', () async {
    for (final status in [404, 410, 403, 503]) {
      final actions = _Actions();
      final sdk = _Sdk();
      final client = _Client(status);
      final media = VoiceMessageMedia(message(),
          actions: actions, sdk: sdk, clientFactory: () => client);
      for (var retry = 0; retry < 2; retry++) {
        await expectLater(
            media.load(),
            throwsA(isA<VoiceMediaFailure>().having(
                (e) => e.expired, 'expired', status == 404 || status == 410)));
      }
      expect(actions.calls, 2);
      expect(sdk.urlReads, 2);
      expect(client.closed, isTrue);
    }
  });

  test('已播放只合并最低位，保留已有标记及ASR，写失败可重试', () async {
    final sdk = _Sdk();
    final media = VoiceMessageMedia(message(), actions: _Actions(), sdk: sdk);
    expect(await media.wasPlayed(), isFalse);
    await media.markPlayed();
    expect(await media.wasPlayed(), isTrue);
    expect(sdk.raw.localCustomInt, 5);
    expect(sdk.raw.localCustomData, '{"voice_to_text":"已有识别"}');
    await media.markPlayed();
    expect(sdk.writes, 1);
    sdk.raw.localCustomInt = 4;
    sdk.code = 1;
    await media.markPlayed();
    expect(sdk.raw.localCustomInt, 4);
    sdk.code = 0;
    await media.markPlayed();
    expect(sdk.raw.localCustomInt, 5);
  });
}
