/// 将会话及搜索摘要中的换行替换为空格，保留链接和消息原文。
String singleLineConversationPreview(String text) =>
    text.replaceAll(RegExp(r'\r\n|\r|\n'), ' ');

/// 语音会话摘要保留标签后的空格和设计秒号；旧缓存时长未知时只显示原标签。
String voiceConversationPreview(String label, int? durationSeconds) =>
    durationSeconds == null
        ? label
        : "$label ${durationSeconds.clamp(0, 60)}''";
