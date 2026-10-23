import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

void main() {
  test('摘要按一个换行替换一个空格且保持URL原样', () {
    const source = '甲\r\n乙\r丙\nhttps://example.com/a?q=1';
    expect(
      singleLineConversationPreview(source),
      '甲 乙 丙 https://example.com/a?q=1',
    );
    expect(source, contains('\r\n'));
  });
}
