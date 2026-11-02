import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

/// SDK测试只注入两项业务契约，不反向依赖feature_tim或保留腾讯默认表情。
void configureEmojiFixture() {
  EmojiManager.configure(assetPackage: 'feature_tim', emojis: const [
    EmojiPickerModelItem(
        name: '[ZDEmoji_Like]',
        label: '点赞',
        path: 'assets/images/zd_emoji/zd_emoji_like.png'),
    EmojiPickerModelItem(
        name: '[ZDEmoji_Smile]',
        label: '微笑',
        path: 'assets/images/zd_emoji/zd_emoji_smile.png'),
  ]);
}
