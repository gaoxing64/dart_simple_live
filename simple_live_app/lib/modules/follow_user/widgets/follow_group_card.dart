import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
import 'package:simple_live_app/widgets/shadow_card.dart';

/// 关注页「全部」视图的一个分组卡片：可折叠、成员多列、并且是拖拽换组的落点。
///
/// 头部：`∨/› 箭头 + 组名 + 「● N/M 在播」+ 右侧拖拽把手图标`。
/// 折叠时不再摆成员头像堆叠 —— 那三枚圆片把组名挤成了省略号。
/// 头部点按=折叠、长按（移动端）/右键（桌面端）=重命名；**调序只认右侧那枚
/// [Icons.drag_handle] 把手**（与「主页排序」同款），整条头部不再可拖 —— 否则
/// 桌面端鼠标左键拖拽 / 移动端竖向滑动都会和调序抢手势。
///
/// 重命名走头部长按/右键、删除与分组管理走右上角「分组管理」，卡片本身不再带
/// ⋮ 操作菜单（那些入口在别处都有，重复提供反而拥挤）。
///
/// 折叠用 `ClipRect + AnimatedSize` 而不是 `ExpansionTile`：后者的
/// theming / ink / tile-padding 与卡片设计冲突，仓库里它也只出现在
/// 解析页与播放器 OSD 这类标准列表场景。
class FollowGroupCard extends StatelessWidget {
  final FollowGroup group;
  final bool collapsed;

  /// 拖拽调序用的索引；null = 禁用调序（搜索中，卡片序号与标签序号对不上）。
  final int? reorderIndex;

  final VoidCallback onToggleCollapsed;

  /// 重命名本分组（头部长按 / 右键触发）。
  final VoidCallback onRename;

  /// 成员被拖到本卡片上（换组）。
  final ValueChanged<FollowUser> onDropMember;
  final ValueChanged<FollowUser> onMemberTap;
  final ValueChanged<FollowUser> onMemberLongPress;
  final ValueChanged<FollowUser>? onMemberRemove;

  /// 快速重组：勾选集合 + 点头像回调。传 null 则成员行不带勾选。
  final RxSet<String>? selectedIds;
  final ValueChanged<FollowUser>? onToggleSelect;

  /// 成员列数（桌面端与未分组紧凑行同一列数口径，移动端为 1）。
  final int memberColumns;

  const FollowGroupCard({
    required this.group,
    required this.collapsed,
    required this.reorderIndex,
    required this.onToggleCollapsed,
    required this.onRename,
    required this.onDropMember,
    required this.onMemberTap,
    required this.onMemberLongPress,
    this.onMemberRemove,
    this.selectedIds,
    this.onToggleSelect,
    this.memberColumns = 1,
    super.key,
  });

  static const double headerHeight = 52;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<FollowUser>(
      // 同组成员拖回本组 = 无操作，不显示高亮。
      onWillAcceptWithDetails: (details) => details.data.tag != group.tag.tag,
      onAcceptWithDetails: (details) => onDropMember(details.data),
      builder: (context, candidates, _) {
        final highlighted = candidates.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            borderRadius: AppStyle.radius12,
            border: Border.all(
              color: highlighted ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: ShadowCard(
            radius: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                    height: headerHeight, child: _buildHeader(context, scheme)),
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubicEmphasized,
                    alignment: Alignment.topCenter,
                    child: collapsed
                        ? const SizedBox(width: double.infinity)
                        : _buildBody(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme) {
    final index = reorderIndex;
    return InkWell(
      borderRadius: AppStyle.radius12,
      onTap: onToggleCollapsed,
      onLongPress: onRename,
      // 桌面端右键 = 长按，和列表别处保持一致。
      onSecondaryTap: onRename,
      child: Padding(
        padding: AppStyle.edgeInsetsH12,
        child: Row(
          children: [
            // 左侧内容整体吃满「除把手外」的宽度：内容短时段落与把手之间留白，
            // 内容长时组名 / 统计各自出省略号，把手始终贴右边缘。
            Expanded(
              child: Row(
                children: [
                  AnimatedRotation(
                    // 展开时箭头朝下，折叠时朝右（设计稿）。
                    turns: collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(Icons.expand_more,
                        color: scheme.onSurfaceVariant),
                  ),
                  AppStyle.hGap8,
                  Flexible(
                    child: Text(
                      group.tag.tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  AppStyle.hGap8,
                  // 计数压成一段 `● 3/4 在播`：原来「3 个正在直播」+「共 4 位」
                  // 两段中文占了大半行，组名只能出省略号（移动端实测）。
                  Flexible(
                    child: selectedIds == null
                        ? FollowCountLabel(
                            live: group.liveCount, total: group.totalCount)
                        : Obx(() {
                            // 勾选数（`· 已选 X`）：勾选集合是 RxSet，卡片又在
                            // 惰性 itemBuilder 里构建，必须自带 Obx 才订阅得到。
                            final sel = group.members
                                .where((m) => selectedIds!.contains(m.id))
                                .length;
                            return FollowCountLabel(
                              live: group.liveCount,
                              total: group.totalCount,
                              selected: sel,
                            );
                          }),
                  ),
                ],
              ),
            ),
            // 右侧专用拖拽把手（与「主页排序」同款）：只有拖这枚图标才调序。
            // 整条头部不再可拖，桌面端鼠标左键拖拽 / 移动端竖向滑动就不会和
            // 调序抢手势。搜索中（index 为 null）不显示把手。
            if (index != null)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 14),
                  child: Icon(Icons.drag_handle,
                      color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: AppStyle.edgeInsetsH12.copyWith(top: 4, bottom: 8),
      child: GridView.count(
        // 必须显式给：`padding` 为 null 时 `ScrollView` 会拿
        // `MediaQuery.padding` 的**主轴分量**（这里就是顶/底安全区，含悬浮底栏
        // 那一段）当默认内边距，而外层是 `CustomScrollView`（它不做这件事），
        // 于是那一段高度一路传到卡片里，每张卡片底部凭空多出一截空白。
        padding: EdgeInsets.zero,
        crossAxisCount: memberColumns,
        shrinkWrap: true,
        // 外层 PageGridView 已有滚动，这里只是把成员摆成多列。
        physics: const NeverScrollableScrollPhysics(),
        mainAxisExtent: FollowMemberRow.rowExtent,
        crossAxisSpacing: 12,
        children: [
          for (final m in group.members)
            // 每行自带 Obx：勾选态是惰性构建里读的，外层 Obx 登记不到。
            Obx(
              () => FollowMemberRow(
                key: ValueKey(m.id),
                item: m,
                liveRing: true,
                draggable: true,
                selected: selectedIds?.contains(m.id) ?? false,
                onToggleSelect:
                    onToggleSelect == null ? null : () => onToggleSelect!(m),
                onTap: () => onMemberTap(m),
                onLongPress: () => onMemberLongPress(m),
                onRemove:
                    onMemberRemove == null ? null : () => onMemberRemove!(m),
              ),
            ),
        ],
      ),
    );
  }
}

/// 分组卡片头部与未分组段头共用的计数：`● 3/4 在播`（+ 勾选态 `· 已选 2`）。
///
/// 圆点只在有在播成员时出现并取主题色，零在播就是灰字 `0/3 在播` —— 两种情况下
/// 这段文字的宽度都稳定，不会因为有组在播就把组名挤成省略号。
class FollowCountLabel extends StatelessWidget {
  final int live;
  final int total;
  final int selected;

  const FollowCountLabel({
    required this.live,
    required this.total,
    this.selected = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // 空组（未分组清空后仍要留作拖拽落点）不显示计数，`0/0 在播` 是噪音。
    if (total == 0) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        children: [
          if (live > 0)
            TextSpan(
              text: '● ',
              style: TextStyle(fontSize: 10, color: scheme.primary),
            ),
          TextSpan(
            text: '$live/$total 在播',
            style: live > 0 ? TextStyle(color: scheme.primary) : null,
          ),
          if (selected > 0) TextSpan(text: ' · 已选 $selected'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
