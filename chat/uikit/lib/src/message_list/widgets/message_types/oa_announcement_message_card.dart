import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../utils/oa_announcement_message.dart';

/// 通知页面共用的公告类型头像，不读取发送者头像或员工资料。
final class OaAnnouncementAvatar extends StatelessWidget {
  const OaAnnouncementAvatar({super.key, this.size = 40});

  /// 头像逻辑像素边长，消息、列表与设置分别由调用方指定。
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.appColors.warning,
          ),
          child: Icon(
            AppIcons.notice,
            size: size / 2,
            color: context.appColors.onPrimary,
          ),
        ),
      );
}

/// 展示单聊公告快照与业务阅读状态，只把详情操作交还宿主。
final class OaAnnouncementMessageCard extends StatelessWidget {
  const OaAnnouncementMessageCard({
    super.key,
    required this.announcement,
    required this.maxWidth,
    required this.onOpen,
    required this.detailIdentifier,
    this.isRead,
  });

  /// 已通过消息类型和协议校验的公告快照，不请求完整详情。
  final OaAnnouncementMessage announcement;

  /// 消息列可用宽度；卡片最多使用设计中的 310 逻辑像素。
  final double maxWidth;

  /// 公告业务阅读状态；null 表示未知，与 IM 回执和会话未读数无关。
  final bool? isRead;

  /// 点击仅触发宿主入口，不在卡片内标记已读。
  final VoidCallback onOpen;

  /// 同页每条消息的详情按钮使用独立且稳定的原生语义标识。
  final String detailIdentifier;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: maxWidth.clamp(0.0, 310.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              // 节点标题外层下边距 8 与卡片间距 14 合并；摘要按原文自然增长。
              const SizedBox(height: 22),
              Text(
                announcement.summary,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 保留阅读状态区域，标题超长时省略，未知状态不能显示成未读。
  Widget _buildHeader(BuildContext context) {
    final colors = context.appColors;
    return Container(
      // 设计标题内外层各有 8 的上边距，此处合并嵌套并保留底部分隔线位置。
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.notice, size: 20, color: colors.warning),
          const SizedBox(width: 4),
          // 标题使用状态区域之外的剩余宽度，窄屏也保留完整阅读状态。
          Expanded(
            child: Text(
              announcement.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            container: true,
            label: isRead == null ? '阅读状态未知' : null,
            excludeSemantics: isRead == null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isRead != null) ...[
                  Icon(
                    isRead! ? AppIcons.read : AppIcons.unread,
                    size: 16,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: 2),
                ],
                Text(
                  isRead == null ? '—' : (isRead! ? '已读' : '未读'),
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 14,
                    height: 20 / 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 发布人快照让出按钮宽度；姓名缺失时不伪造发布人。
  Widget _buildFooter(BuildContext context) {
    final colors = context.appColors;
    final publisher = announcement.publisherName;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: Row(
        children: [
          // 长姓名只占按钮之外的空间，避免挤掉唯一的详情入口。
          Expanded(
            child: Text(
              publisher.isEmpty ? '' : '$publisher 发布',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
                height: 20 / 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onOpen,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: colors.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: const TextStyle(fontSize: 14, height: 20 / 14),
            ),
            // 标识加入按钮自身的语义边界，和按钮文字、点击动作合并，不能落到整卡。
            child: Semantics(
              identifier: detailIdentifier,
              child: const Text('查看详情'),
            ),
          ),
        ],
      ),
    );
  }
}
