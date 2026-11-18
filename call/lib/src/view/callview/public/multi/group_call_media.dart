import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'group_call_member.dart';
import 'group_call_member_tile.dart';

/// 群通话的双人、2×2、九格和大画面布局，选择状态仅属于当前展示组件。
class GroupCallMedia extends StatefulWidget {
  const GroupCallMedia(
      {super.key,
      required this.members,
      required this.videoBuilder,
      this.initialFocusedId,
      this.onRetry});

  /// 按当前场次顺序排列的成员，最多显示9人。
  final List<GroupCallMember> members;

  /// 恢复展示或离线审阅时指定初始大画面，不改变 SDK 媒体选择。
  final String? initialFocusedId;

  /// 外层为每个用户持有稳定视频Key，移动画面不会创建第二路订阅。
  final Widget Function(String userId) videoBuilder;

  /// 拒绝、超时等成员在有效场次内的追加邀请入口。
  final ValueChanged<String>? onRetry;

  @override
  State<GroupCallMedia> createState() => _GroupCallMediaState();
}

/// 仅保存选中的大画面，不复制成员和设备业务状态。
class _GroupCallMediaState extends State<GroupCallMedia> {
  /// 本地大画面选择，在成员离开可见列表后自动回到宫格。
  String? _focusedId;

  @override
  void initState() {
    super.initState();
    _focusedId = widget.initialFocusedId;
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members.take(9).toList(growable: false);
    final focused = members.where((m) => m.id == _focusedId).firstOrNull;
    if (members.isEmpty) return const SizedBox.shrink();
    return focused == null ? _grid(members) : _focused(members, focused);
  }

  Widget _grid(List<GroupCallMember> members) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = members.length <= 4 ? 2 : 3;
          final gap = columns == 3 ? 4.0 : 0.0;
          final padding = columns == 3 ? 4.0 : 0.0;
          final rows = (members.length / columns).ceil();
          final side = math.min(
            (constraints.maxWidth - padding * 2 - gap * (columns - 1)) /
                columns,
            (constraints.maxHeight - gap * (rows - 1)) / rows,
          );
          // 双人卡片从媒体区顶向下 110 像素，不能随页面余高垂直居中。
          final top = members.length <= 2
              ? math.min(110.0, math.max(0.0, constraints.maxHeight - side))
              : 0.0;
          return Align(
            alignment: Alignment.topCenter,
            child: Padding(
                padding: EdgeInsets.only(top: top),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: side * rows + gap * (rows - 1),
                  child: GridView.builder(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: members.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: side,
                      mainAxisSpacing: gap,
                      crossAxisSpacing: gap,
                    ),
                    itemBuilder: (context, index) => _tile(members[index]),
                  ),
                )),
          );
        },
      );

  /// 主图和缩略条使用设计的 340/94 像素高度，额外屏高留在媒体区下方。
  Widget _focused(List<GroupCallMember> members, GroupCallMember focused) =>
      LayoutBuilder(builder: (context, constraints) {
        final stripHeight = math.min(94.0, constraints.maxHeight);
        final mainHeight =
            math.min(340.0, math.max(0.0, constraints.maxHeight - stripHeight));
        return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: mainHeight + stripHeight,
              child: Column(children: [
                // 主画面和其缩略图不会同时绑定同一视频纹理。
                SizedBox(
                    height: mainHeight,
                    child: _tile(focused,
                        mainView: true,
                        onTap: () => setState(() => _focusedId = null))),
                SizedBox(
                    height: stripHeight,
                    // 双人大图只显示另一人的缩略；多人保留选中缩略与绿色边框。
                    child: _thumbnails(
                        members.length == 2
                            ? members
                                .where((member) => member.id != focused.id)
                                .toList()
                            : members,
                        focused.id)),
              ]),
            ));
      });

  Widget _thumbnails(List<GroupCallMember> members, String focusedId) =>
      ListView.separated(
        scrollDirection: Axis.horizontal,
        // 最多九人，保留视口外本端纹理，避免切大画面时无法确认本地开摄像头。
        cacheExtent: 9 * 98,
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final member = members[index];
          final selected = member.id == focusedId;
          return SizedBox(
              width: 94,
              child: GroupCallMemberTile(
                member: member,
                thumbnail: true,
                selected: selected,
                showVideo: !selected,
                video: selected
                    ? const SizedBox.shrink()
                    : widget.videoBuilder(member.id),
                onTap: () => setState(() => _focusedId = member.id),
              ));
        },
      );

  Widget _tile(GroupCallMember member,
          {VoidCallback? onTap, bool mainView = false}) =>
      GroupCallMemberTile(
        key: ValueKey(member.id),
        member: member,
        mainView: mainView,
        video: widget.videoBuilder(member.id),
        onTap: onTap ??
            (member.joined
                ? () => setState(() => _focusedId = member.id)
                : null),
        onRetry:
            widget.onRetry == null ? null : () => widget.onRetry!(member.id),
      );
}
