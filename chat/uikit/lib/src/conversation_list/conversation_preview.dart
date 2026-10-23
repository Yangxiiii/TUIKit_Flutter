/// 将会话及搜索摘要中的换行替换为空格，保留链接和消息原文。
String singleLineConversationPreview(String text) =>
    text.replaceAll(RegExp(r'\r\n|\r|\n'), ' ');
