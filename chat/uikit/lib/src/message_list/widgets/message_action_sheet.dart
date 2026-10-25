import 'dart:async';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import '../../emoji_picker/emoji_picker_model.dart';
import '../utils/recent_emoji_manager.dart';
import 'message_tooltip.dart';

/// 仅展示设计定义的消息操作分组；业务沿用气泡回调，未接入的动作保持禁用。
class MessageActionSheet extends StatefulWidget {
  const MessageActionSheet({
    super.key,
    required this.items,
    required this.onClose,
    required this.onBounds,
    this.onReaction,
    this.onMoreReactions,
    this.editExpiresAt,
  });

  /// 以稳定动作标识匹配已有复制、转发、回复等能力，不通过翻译后的文字推断。
  final List<MessageMenuItem> items;

  /// 点击动作前关闭面板，防止异步导航仍被底部路由遮挡。
  final VoidCallback onClose;

  /// 实测面板最上沿，包括拖拽条区域，供聊天页避让目标。
  final ValueChanged<Rect> onBounds;

  /// SDK支持回应时复用原有添加/撤销回应流程。
  final void Function(EmojiPickerModelItem)? onReaction;

  /// 打开TUIKit完整表情面板，表情资源不另外复制或导出。
  final VoidCallback? onMoreReactions;

  /// 原发送时间加五分钟；菜单已打开时到期只禁用编辑，不移除该行。
  final DateTime? editExpiresAt;

  @override
  State<MessageActionSheet> createState() => _MessageActionSheetState();
}

/// 加载TUIKit近期表情，并报告实际面板边界；不保存消息编辑业务状态。
class _MessageActionSheetState extends State<MessageActionSheet> {
  final GlobalKey _bounds = GlobalKey();

  /// 当前面板的六个快捷表情，缓存随面板销毁，不影响编辑次数。
  List<EmojiPickerModelItem> _emojis = [];
  bool _loaded = false;

  /// 只负责菜单资格到期后的重绘，实际保存资格仍由SDK服务复核。
  Timer? _expiryTimer;

  /// 到期后保持菜单行可见并禁用点击，直到本次面板被销毁。
  bool _editExpired = false;

  /// 底部路由的位移动画不一定重建面板，需逐帧重测实际屏幕顶部。
  Animation<double>? _routeAnimation;
  bool _boundsScheduled = false;

  @override
  void initState() {
    super.initState();
    final expiry = widget.editExpiresAt;
    if (expiry != null) {
      final remaining = expiry.difference(DateTime.now());
      if (remaining.isNegative) {
        _editExpired = true;
      } else {
        _expiryTimer = Timer(remaining, () {
          if (mounted) {
            setState(() => _editExpired = true);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _routeAnimation?.removeListener(_scheduleBounds);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeListener(_scheduleBounds);
      _routeAnimation = animation;
      animation?.addListener(_scheduleBounds);
    }
    if (!_loaded) {
      _loaded = true;
      // 近期记录读取失败仍保留默认TUIKit表情，不能阻断消息操作。
      _emojis = RecentEmojiManager.getAllEmojis(context).take(6).toList();
      unawaited(_loadRecentEmojis());
    }
  }

  /// 近期记录只改变排序，存储失败不影响已加载的默认表情或其余消息操作。
  Future<void> _loadRecentEmojis() async {
    try {
      final value = await RecentEmojiManager.getQuickEmojis(context);
      if (mounted) {
        setState(() => _emojis = value.take(6).toList());
      }
    } on Object {
      debugPrint('读取消息快捷表情失败，保留默认表情');
    }
  }

  /// 动画布局后测量；退场不再抢占已经进入编辑态的浮层边界。
  void _scheduleBounds() {
    if (_boundsScheduled ||
        _routeAnimation?.status == AnimationStatus.reverse) {
      return;
    }
    _boundsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _boundsScheduled = false;
      if (!mounted) {
        return;
      }
      final box = _bounds.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        widget.onBounds(box.localToGlobal(Offset.zero) & box.size);
      }
    });
  }

  MessageMenuItem? _item(String id) {
    for (final item in widget.items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  /// 先关闭底部路由再沿用业务操作，避免转发等后续页面被面板覆盖。
  void _activate(String id) {
    final item = _item(id);
    if (item == null) {
      return;
    }
    widget.onClose();
    item.onTap();
  }

  /// 同一动作支持快捷卡片与分组行；无业务回调或编辑到期时保留禁用展示。
  Widget _action(String id, String title, IconData icon, {bool quick = false}) {
    final colors = context.appColors;
    final enabled = _item(id) != null && (id != 'edit' || !_editExpired);
    return Semantics(
      identifier: 'tim.message.action.$id',
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? () => _activate(id) : null,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: quick ? 80 : 48,
          // 快捷动作上下排列，普通动作保持左图标右文案的分组行。
          child: quick
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon,
                      size: 24,
                      color:
                          enabled ? colors.textPrimary : colors.textTertiary),
                  const SizedBox(height: 4),
                  Text(title,
                      style: TextStyle(
                          fontSize: 12,
                          color: enabled
                              ? colors.textPrimary
                              : colors.textTertiary)),
                ])
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Icon(icon,
                        size: 24,
                        color:
                            enabled ? colors.textPrimary : colors.textTertiary),
                    const SizedBox(width: 8),
                    Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            color: enabled
                                ? colors.textPrimary
                                : colors.textTertiary)),
                  ]),
                ),
        ),
      ),
    );
  }

  Widget _group(List<Widget> children) => DecoratedBox(
        decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                  padding: const EdgeInsets.only(left: 16, right: 12),
                  child: Divider(
                      height: 0,
                      thickness: 0.5,
                      color: context.appColors.outline)),
            children[i],
          ]
        ]),
      );

  /// 六个TUIKit表情与圆形更多占七列，设计宽度下自动分配22像素间隔。
  Widget _buildEmojis() {
    final colors = context.appColors;
    return SizedBox(
        height: 32,
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final emoji in _emojis)
            Semantics(
              identifier: 'tim.message.reaction.${emoji.name}',
              button: true,
              child: GestureDetector(
                  onTap: widget.onReaction == null
                      ? null
                      : () {
                          widget.onClose();
                          widget.onReaction!(emoji);
                        },
                  child: Image.asset(emoji.path,
                      package: 'tencent_chat_uikit', width: 32, height: 32)),
            ),
          Semantics(
              identifier: 'tim.message.reactionsMore',
              button: true,
              child: InkWell(
                onTap: widget.onMoreReactions,
                child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: colors.outline, shape: BoxShape.circle),
                    child: Icon(AppIcons.more,
                        size: 20, color: colors.textPrimary)),
              )),
        ]));
  }

  /// 四个快捷动作等宽排列，原有业务回调缺失时保留设计禁用态。
  Widget _buildQuickActions() {
    final colors = context.appColors;
    return Row(children: [
      for (final entry in [
        ('reply', '回复', AppIcons.reply),
        ('forward', '转发', AppIcons.forward),
        ('mark', '标记', AppIcons.mark),
        ('copy', '复制', AppIcons.copy)
      ]) ...[
        if (entry.$1 != 'reply') const SizedBox(width: 8),
        Expanded(
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8)),
                child: _action(entry.$1, entry.$2, entry.$3, quick: true))),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleBounds();
    final colors = context.appColors;
    return Material(
      key: _bounds,
      color: colors.referenceBackground,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
          height: 541,
          child: Stack(children: [
            // 拖拽条不占据内容高度，面板全部区域都参与遮挡测量。
            Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                    child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: colors.textSecondary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20)),
                ))),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: SingleChildScrollView(
                    child: Column(children: [
                  _buildEmojis(),
                  const SizedBox(height: 15),
                  _buildQuickActions(),
                  const SizedBox(height: 15),
                  _group([
                    _action('recall', '撤回', AppIcons.recall1),
                    // 只有符合消息类型、所有权和时限时才展示编辑入口。
                    if (_item('edit') != null)
                      _action('edit', '编辑消息', AppIcons.editMessage),
                    _action('urgent', '加急', AppIcons.urgent),
                    // selected字形内含数字1，多选操作使用不带计数的复选列表字形。
                    _action('multiSelect', '多选', AppIcons.multipleChoice),
                  ]),
                  const SizedBox(height: 15),
                  _group([
                    _action('top', '置顶消息', AppIcons.topMessage),
                    _action('pin', 'Pin', AppIcons.pin),
                    _action('delete', '删除', AppIcons.delete)
                  ]),
                ]))),
          ])),
    );
  }
}
