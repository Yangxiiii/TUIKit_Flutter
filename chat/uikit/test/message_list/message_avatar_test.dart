import 'package:app_ui/app_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

const _profileAvatar = 'https://example.com/profile.png';
const _rawAvatar = 'https://example.com/raw.png';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> mount(WidgetTester tester, MessageInfo message,
          {String alignment = 'two-sided'}) =>
      tester.pumpWidget(MaterialApp(
        theme: AppThemeFactory.create(
            const AppNormalColorScheme(), Brightness.light),
        home: Scaffold(
            body: MessageItem(
          message: message,
          conversationID: 'c2c_peer',
          messageListStore: _ListStore(),
          isHighlighted: false,
          config: ChatMessageListConfig(
            alignment: alignment,
            isShowLeftAvatar: true,
            isShowRightAvatar: true,
            enableReadReceipt: false,
          ),
        )),
      ));

  testWidgets('上传占位、SDK 发送与完成阶段共用发送者头像，原始空值或旧值不覆盖', (tester) async {
    final cache = PaintingBinding.instance.imageCache;
    addTearDown(() {
      cache.clear();
      cache.clearLiveImages();
    });
    final image = (await tester.runAsync(() => createTestImage()))!;
    cache.putIfAbsent(
        const CachedNetworkImageProvider(_profileAvatar),
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: image))));
    for (final alignment in ['two-sided', 'left', 'right']) {
      for (final stage in [
        (MessageStatus.sending, null),
        (MessageStatus.sending, ''),
        (MessageStatus.sending, _rawAvatar),
        (MessageStatus.sendSuccess, _rawAvatar),
        (MessageStatus.sendFail, ''),
      ]) {
        final message = MessageInfo(
          msgID: 'self',
          isSentBySelf: true,
          status: stage.$1,
          from: MessageSenderInfo(
              userID: 'self', nickname: '本人', avatarURL: _profileAvatar),
          messageType: MessageType.text,
          messagePayload: TextMessagePayload(text: '发送内容'),
          rawMessage: stage.$2 == null ? null : _RawMessage(stage.$2),
        );
        await mount(tester, message, alignment: alignment);
        final avatar = tester.widget<Avatar>(find.byType(Avatar));
        expect((avatar.content as AvatarImageContent).url, _profileAvatar,
            reason: '$alignment ${stage.$1} ${stage.$2}');
        expect((avatar.content as AvatarImageContent).name, '本人');
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('发送者头像缺省时回退原始消息头像，双方均缺省时仍使用默认头像', (tester) async {
    for (final profile in <String?>[null, '']) {
      for (final raw in <String?>[_rawAvatar, null]) {
        await mount(
            tester,
            MessageInfo(
              msgID: 'peer',
              from: MessageSenderInfo(
                  userID: 'peer', nickname: '同事', avatarURL: profile),
              messageType: MessageType.text,
              messagePayload: TextMessagePayload(text: '接收内容'),
              rawMessage: _RawMessage(raw),
            ));
        final avatar = tester.widget<Avatar>(find.byType(Avatar));
        final url = (avatar.content as AvatarImageContent).url;
        expect(raw == null ? url == null || url.isEmpty : url == raw, isTrue);
        expect((avatar.content as AvatarImageContent).name, '同事');
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('默认文字头像的名称保留群名片、好友备注和昵称的优先级', (tester) async {
    final sender = MessageSenderInfo(
        userID: 'peer', nickname: '昵称', friendRemark: '备注', nameCard: '群名片');
    for (final expected in ['群名片', '备注', '昵称', 'peer']) {
      await mount(
          tester,
          MessageInfo(
            msgID: 'peer',
            from: sender,
            messageType: MessageType.text,
            messagePayload: TextMessagePayload(text: '内容'),
          ));
      final avatar = tester.widget<Avatar>(find.byType(Avatar));
      expect((avatar.content as AvatarImageContent).name, expected);
      switch (expected) {
        case '群名片':
          sender.nameCard = '';
        case '备注':
          sender.friendRemark = null;
        case '昵称':
          sender.nickname = '';
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _ListStore implements MessageListStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 只提供渲染字段，避免 SDK 消息构造函数读取原生服务器时间。
class _RawMessage implements V2TimMessage {
  _RawMessage(this.faceUrl);

  @override
  final String? faceUrl;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      switch (invocation.memberName) {
        #elemType => 1,
        #sender => 'self',
        _ => null,
      };
}
