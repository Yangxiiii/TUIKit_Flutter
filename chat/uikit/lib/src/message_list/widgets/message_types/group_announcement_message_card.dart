import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 展示群聊公告的纯文本摘要，整卡沿用宿主的公告详情入口。
final class GroupAnnouncementMessageCard extends StatelessWidget {
  const GroupAnnouncementMessageCard({
    super.key,
    required this.summary,
    required this.maxWidth,
    required this.onOpen,
    this.onLongPress,
  });

  /// 卡片摘要以两行显示，正文由详情接口读取。
  final String summary;

  /// 外层消息行提供的可用宽度，单位为逻辑像素。
  final double maxWidth;

  /// 详情由当前群宿主打开，历史预览可只展示卡片。
  final VoidCallback? onOpen;

  /// 保留原消息菜单中允许的其他操作。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final shape = RoundedRectangleBorder(
      side: BorderSide(color: colors.outline),
      borderRadius: BorderRadius.circular(8),
    );
    return Material(
      color: colors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
        child: SizedBox(
          width: maxWidth.clamp(0.0, 262.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 标题和喇叭同属卡片导航，分隔线以下只显示公告摘要。
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(AppIcons.voiceOn,
                            size: 16, color: colors.warning),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '群公告',
                          style: TextStyle(
                              color: colors.textPrimary, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                ColoredBox(
                    color: colors.outline, child: const SizedBox(height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      height: 20 / 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
