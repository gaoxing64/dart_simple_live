import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/widgets/filter_button.dart';
import 'package:simple_live_app/widgets/net_image.dart';

/// 「一键成组」bottom sheet（设计稿样式）：
/// 输入分组名称 → 创建并把已勾选的主播加入；
/// 或点已有分组 / 「全部（移出分组）」chip 把已勾选成员批量移过去。
class FollowQuickGroupSheet extends StatefulWidget {
  final List<FollowUser> selected;
  final List<FollowUserTag> existingTags;

  /// 内置「全部」标签（移出分组的目标）。
  final FollowUserTag ungroupTag;

  /// 返回是否创建成功（成功才关闭 sheet）。
  final Future<bool> Function(String name) onCreate;
  final Future<void> Function(FollowUserTag tag) onMoveTo;

  const FollowQuickGroupSheet({
    required this.selected,
    required this.existingTags,
    required this.ungroupTag,
    required this.onCreate,
    required this.onMoveTo,
    super.key,
  });

  @override
  State<FollowQuickGroupSheet> createState() => _FollowQuickGroupSheetState();
}

class _FollowQuickGroupSheetState extends State<FollowQuickGroupSheet> {
  final _nameController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await widget.onCreate(_nameController.text);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (ok && mounted) {
      Get.back();
    }
  }

  Future<void> _moveTo(FollowUserTag tag) async {
    await widget.onMoveTo(tag);
    if (mounted) {
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = widget.selected.length;
    return SafeArea(
      top: false,
      child: Padding(
        // 键盘弹出时把表单顶起来
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // sheet 顶部拖拽把手（纯装饰，与弹窗动画配套）
            Center(
              child: Container(
                margin: AppStyle.edgeInsetsV8,
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: AppStyle.radius24,
                ),
              ),
            ),
            Padding(
              padding: AppStyle.edgeInsetsA16.copyWith(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '一键成组',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  AppStyle.vGap12,
                  Text(
                    '分组名称',
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  AppStyle.vGap8,
                  TextField(
                    key: const Key('quick-group-name-field'),
                    controller: _nameController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _create(),
                    decoration: InputDecoration(
                      hintText: "例如：CS解说",
                      prefixIcon: const Icon(Remix.folder_3_line),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: AppStyle.radius12,
                      ),
                    ),
                  ),
                  AppStyle.vGap12,
                  Row(
                    children: [
                      _AvatarPreview(users: widget.selected),
                      AppStyle.hGap8,
                      Expanded(
                        child: Text(
                          "将已选的 $n 位主播加入该分组，原分组中的成员不受影响",
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppStyle.vGap12,
                  Text(
                    '或移入已有分组',
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  AppStyle.vGap8,
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final t in widget.existingTags)
                        FilterButton(
                          text: t.tag,
                          onTap: () => _moveTo(t),
                        ),
                      FilterButton(
                        text: '全部（移出分组）',
                        onTap: () => _moveTo(widget.ungroupTag),
                      ),
                    ],
                  ),
                  AppStyle.vGap12,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: Get.back,
                        child: const Text('取消'),
                      ),
                      AppStyle.hGap8,
                      FilledButton(
                        onPressed: _busy ? null : _create,
                        child: const Text('创建分组'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹窗里的已选头像预览堆叠（最多 4 个，重叠圆片）。
class _AvatarPreview extends StatelessWidget {
  final List<FollowUser> users;
  const _AvatarPreview({required this.users});

  static const double _size = 22;
  static const double _step = 16;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = users.take(4).toList();
    return SizedBox(
      height: _size,
      width: _size + _step * (shown.length - 1),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * _step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: NetImage(
                  shown[i].face,
                  width: _size,
                  height: _size,
                  borderRadius: _size / 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
