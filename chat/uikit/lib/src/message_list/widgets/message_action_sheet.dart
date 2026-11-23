import 'dart:async';
import 'dart:math' as math;
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
import '../../emoji_picker/emoji_picker_model.dart';
import '../utils/recent_emoji_manager.dart';
import 'message_tooltip.dart';
import 'reaction_emoji_picker.dart';

/// 在同一个可拖拽面板内展示消息操作或完整表情，动作仍交给气泡回调处理。
class MessageActionSheet extends StatefulWidget {
  const MessageActionSheet({
    super.key,
    required this.items,
    required this.onClose,
    required this.onBounds,
    this.onReaction,
    this.editExpiresAt,
    this.recallExpiresAt,
    this.onExpansionChanged,
  });

  /// 以稳定动作标识匹配已有复制、转发、回复等能力，不通过翻译后的文字推断。
  final List<MessageMenuItem> items;

  /// 点击动作前关闭面板，防止异步导航仍被底部路由遮挡。
  final VoidCallback onClose;

  /// 根据实测面板底部报告初始高度的边界，供聊天页在打开菜单时避让。
  final ValueChanged<Rect> onBounds;

  /// SDK支持回应时复用原有添加/撤销回应流程。
  final void Function(EmojiPickerModelItem)? onReaction;

  /// 展开进度从紧凑高度的零变化到最高位置的一，供路由更新遮罩。
  final ValueChanged<double>? onExpansionChanged;

  /// 原发送时间加五分钟；菜单已打开时到期只禁用编辑，不移除该行。
  final DateTime? editExpiresAt;

  /// 原发送时间加两分钟；到期立即移除撤回行，提交时仍须重查SDK。
  final DateTime? recallExpiresAt;

  /// 打开唯一的底部路由，切换内容期间持续报告气泡避让边界。
  static Future<void> show(
    BuildContext context, {
    required List<MessageMenuItem> items,
    required ValueChanged<Rect> onBounds,
    ValueChanged<EmojiPickerModelItem>? onReaction,
    DateTime? editExpiresAt,
    DateTime? recallExpiresAt,
  }) {
    final navigator = Navigator.of(context);
    final localizations = MaterialLocalizations.of(context);
    late final _MessageActionSheetRoute route;
    route = _MessageActionSheetRoute(
      scrim: context.appColors.scrim,
      capturedThemes:
          InheritedTheme.capture(from: context, to: navigator.context),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint:
          localizations.scrimOnTapHint(localizations.bottomSheetLabel),
      builder: (sheetContext) => MessageActionSheet(
        items: items,
        onClose: () => Navigator.of(sheetContext).pop(),
        onBounds: onBounds,
        onReaction: onReaction,
        editExpiresAt: editExpiresAt,
        recallExpiresAt: recallExpiresAt,
        onExpansionChanged: route.updateExpansion,
      ),
    );
    return navigator.push(route);
  }

  @override
  State<MessageActionSheet> createState() => _MessageActionSheetState();
}

/// 复用 Flutter 底部路由的进退场和关闭手势，按实际展开进度更新原生遮罩。
class _MessageActionSheetRoute extends ModalBottomSheetRoute<void> {
  _MessageActionSheetRoute({
    required Color scrim,
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.barrierOnTapHint,
  })  : _scrim = scrim,
        super(
          backgroundColor: Colors.transparent,
          enableDrag: false,
          showDragHandle: false,
          isScrollControlled: true,
          useSafeArea: true,
        );

  /// 完全展开时使用的应用通用遮罩色。
  final Color _scrim;

  /// 面板当前介于紧凑与最高位置之间的比例。
  double _expansion = 0;

  @override
  Color get barrierColor => _scrim.withValues(alpha: _scrim.a * _expansion);

  /// 由面板在布局后报告，沿用路由的遮罩动画与关闭语义。
  void updateExpansion(double expansion) {
    if (_expansion == expansion || !isActive) return;
    _expansion = expansion;
    changedInternalState();
  }
}

/// 管理内容切换、操作时限及拖拽收起，分别报告初始避让边界和当前遮罩进度。
class _MessageActionSheetState extends State<MessageActionSheet> {
  /// 菜单内容几何与紧凑高度共用的逻辑像素尺寸。
  static const double _emojiSize = 32;
  static const double _shortcutHeight = 80;
  static const double _rowHeight = 48;
  static const double _groupGap = 15;
  static const double _topPadding = 24;

  /// 定位实际绘制的面板圆角区域，避让测量不包含路由空白。
  final GlobalKey _bounds = GlobalKey();

  /// 读取手势起止时的实际面板高度，普通表情滚动使用同一个位置来源。
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  /// 记录本次手势能否从展开态下滑关闭，短暂上滑后回到原位仍保留菜单。
  bool _dragStartedExpanded = false;

  /// 两种内容共用常用表情列表，快捷行取前六项。
  List<EmojiPickerModelItem> _emojis = [];
  bool _loaded = false;

  /// 当前路由内切换到完整表情内容，沿用已打开面板的拖拽高度。
  bool _showAllReactions = false;

  /// 当前安全区域下的紧凑与最高高度，单位为逻辑像素。
  ({double compact, double max}) _heights = (compact: 0, max: 0);

  /// 只负责菜单资格到期后的重绘，实际保存资格仍由SDK服务复核。
  Timer? _expiryTimer;

  /// 仅负责本次面板的撤回入口到期重绘，不执行SDK动作。
  Timer? _recallExpiryTimer;

  /// 当前菜单是否已越过撤回截止时间；为true时必须移除入口。
  bool _recallExpired = false;

  /// 到期后保持菜单行可见并禁用点击，直到本次面板被销毁。
  bool _editExpired = false;

  /// 底部路由的位移动画不一定重建面板，需逐帧重测实际屏幕顶部。
  Animation<double>? _routeAnimation;

  /// 路由和拖拽可以在同一帧通知，合并后只测量一次。
  bool _boundsScheduled = false;

  @override
  void initState() {
    super.initState();
    final recallRemaining = widget.recallExpiresAt?.difference(DateTime.now());
    if (recallRemaining != null) {
      _recallExpired = recallRemaining <= Duration.zero;
      if (!_recallExpired) {
        _recallExpiryTimer = Timer(recallRemaining, () {
          if (mounted) setState(() => _recallExpired = true);
        });
      }
    }
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
    _recallExpiryTimer?.cancel();
    _expiryTimer?.cancel();
    _routeAnimation?.removeListener(_scheduleBounds);
    _sheetController.dispose();
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
      // 近期记录读取失败仍保留当前目录表情，不能阻断消息操作。
      _emojis = RecentEmojiManager.getAllEmojis(context)
          .take(ReactionEmojiPickerSheet.quickEmojiCount)
          .toList();
      unawaited(_loadRecentEmojis());
    }
  }

  /// 近期记录只改变排序，存储失败不影响已加载的默认表情或其余消息操作。
  Future<void> _loadRecentEmojis() async {
    try {
      final value = await ReactionEmojiPickerSheet.loadQuickEmojis();
      if (mounted) {
        setState(() => _emojis = value);
      }
    } on Object {
      debugPrint('读取消息快捷表情失败，保留默认表情');
    }
  }

  /// 避让沿用菜单打开时的高度，拖拽产生的实际高度只用于遮罩渐变。
  void _scheduleBounds() {
    if (_boundsScheduled ||
        _routeAnimation?.status == AnimationStatus.reverse) {
      return;
    }
    _boundsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _boundsScheduled = false;
      if (!mounted || _routeAnimation?.status == AnimationStatus.reverse) {
        return;
      }
      final box = _bounds.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final bottom = box.localToGlobal(Offset(0, box.size.height));
        widget.onBounds(Rect.fromLTWH(
          bottom.dx,
          bottom.dy - _heights.compact,
          box.size.width,
          _heights.compact,
        ));
        final range = _heights.max - _heights.compact;
        final progress = range > 0
            ? ((box.size.height - _heights.compact) / range).clamp(0.0, 1.0)
            : 0.0;
        widget.onExpansionChanged?.call(progress);
      }
    });
  }

  /// 等 Flutter 结束松手回弹，再判断展开中的菜单是否回到了初始高度。
  bool _handleSheetScroll(ScrollNotification notification) {
    if (notification.depth != 0 || !_sheetController.isAttached) return false;
    // Flutter 可能在离吸附点不到一个逻辑像素时停止回弹。
    final isCompact = _sheetController.pixels <= _heights.compact + 1;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragStartedExpanded = !isCompact;
    } else if (notification is ScrollEndNotification) {
      final shouldClose = _dragStartedExpanded && isCompact;
      _dragStartedExpanded = false;
      if (shouldClose) {
        // 最低档位也可能已经触发路由关闭，避免延后一帧重复返回聊天页。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ModalRoute.isCurrentOf(context) != false) {
            widget.onClose();
          }
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }
    return false;
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

  /// 快捷和完整表情共享同一提交入口，先关闭当前路由再发送回应。
  void _selectReaction(EmojiPickerModelItem emoji) {
    widget.onClose();
    widget.onReaction?.call(emoji);
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
          height: quick ? _shortcutHeight : _rowHeight,
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
    final canReact = widget.onReaction != null;
    return SizedBox(
        height: _emojiSize,
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final emoji in _emojis.take(6))
            Semantics(
              identifier: 'tim.message.reaction.${emoji.name}',
              button: true,
              child: GestureDetector(
                  onTap: canReact ? () => _selectReaction(emoji) : null,
                  child: Image.asset(emoji.path,
                      package: EmojiManager.assetPackage,
                      width: _emojiSize,
                      height: _emojiSize)),
            ),
          Semantics(
              identifier: 'tim.message.reactionsMore',
              button: true,
              enabled: canReact,
              child: InkWell(
                onTap: canReact
                    ? () => setState(() => _showAllReactions = true)
                    : null,
                child: Container(
                    width: _emojiSize,
                    height: _emojiSize,
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

  /// 返回当前动作分组；紧凑高度和布局都以同一批可见行计算。
  List<List<Widget>> _buildActionGroups() {
    final voice = _item('audio-route');
    final asr = _item('voice-text');
    final sticky = _item('top');
    return [
      // 语音能力单独成组，仅当当前消息允许切换播放设备时展示。
      if (voice != null)
        [
          _action('audio-route', voice.title, voice.icon ?? AppIcons.ear),
          if (asr != null)
            _action('voice-text', asr.title, asr.icon ?? AppIcons.format),
        ],
      [
        // 撤回到期移除入口；编辑到期保留行，由动作组件禁用。
        if (_item('recall') != null && !_recallExpired)
          _action('recall', '撤回', AppIcons.recall1),
        if (_item('edit') != null)
          _action('edit', '编辑消息', AppIcons.editMessage),
        _action('urgent', '加急', AppIcons.urgent),
        // 多选使用不带计数的复选列表字形。
        _action('multiSelect', '多选', AppIcons.multipleChoice),
      ],
      [
        _action('top', sticky?.title ?? '置顶消息',
            sticky?.icon ?? AppIcons.topMessage),
        _action('pin', 'Pin', AppIcons.pin),
        _action('delete', '删除', AppIcons.delete),
      ],
    ];
  }

  /// 手柄覆盖滚动区顶部，手势从手柄或动作区起滑都交给同一个滚动控制器。
  Widget _buildActions(ScrollController scrollController,
      List<List<Widget>> groups, double bottomPadding) {
    return Stack(
      fit: StackFit.expand,
      children: [
        SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(16, _topPadding, 16, bottomPadding),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _buildEmojis(),
            const SizedBox(height: _groupGap),
            _buildQuickActions(),
            for (final group in groups) ...[
              const SizedBox(height: _groupGap),
              _group(group),
            ],
          ]),
        ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.appColors.textSecondary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final groups = _buildActionGroups();
    // 系统手势区域和设计底距取较大值，紧凑态保持原有内容高度。
    final bottomPadding =
        math.max(25.0, MediaQuery.viewPaddingOf(context).bottom);
    final rowCount = groups.fold(0, (count, group) => count + group.length);
    final contentHeight = _topPadding +
        _emojiSize +
        _shortcutHeight +
        _groupGap * (groups.length + 1) +
        _rowHeight * rowCount +
        bottomPadding;
    const maxFraction = ReactionEmojiPickerSheet.maxHeightFraction;

    return LayoutBuilder(builder: (context, constraints) {
      final availableHeight = constraints.maxHeight;
      if (availableHeight == 0) return const SizedBox.shrink();
      final compactFraction =
          math.min(contentHeight / availableHeight, maxFraction);
      _heights = (
        compact: availableHeight * compactFraction,
        max: availableHeight * maxFraction,
      );
      _scheduleBounds();

      // 拖拽后的高度变化不一定重建内容，仍需在下一次布局后重测避让边界。
      return NotificationListener<DraggableScrollableNotification>(
        onNotification: (_) {
          _scheduleBounds();
          return false;
        },
        child: DraggableScrollableSheet(
          controller: _sheetController,
          expand: false,
          initialChildSize: compactFraction,
          minChildSize: 0,
          maxChildSize: maxFraction,
          snap: true,
          // 向下拖过紧凑档位可关闭路由；切换为表情时保留当前档位。
          snapSizes: [if (compactFraction < maxFraction) compactFraction],
          builder: (context, scrollController) =>
              NotificationListener<ScrollNotification>(
            onNotification: _handleSheetScroll,
            child: Material(
              key: _bounds,
              color: colors.referenceBackground,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: _showAllReactions
                  ? ReactionEmojiPickerSheet(
                      scrollController: scrollController,
                      quickEmojis: _emojis,
                      onEmojiClick: _selectReaction,
                    )
                  : _buildActions(scrollController, groups, bottomPadding),
            ),
          ),
        ),
      );
    });
  }
}
