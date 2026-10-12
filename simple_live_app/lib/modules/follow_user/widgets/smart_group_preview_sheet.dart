import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/services/smart_group_service.dart';

/// 一键按平台分组：预览 + 确认。
///
/// 把「将发生什么」摊开在点下去之前 —— 这个动作会一次改几十条归属，
/// 没有预览就等于盲操作。已有同名分组标「复用」，新建标「新建」。
class SmartGroupPreviewSheet extends StatefulWidget {
  /// 确认后的实际执行（由调用方负责刷新关注页）。
  final Future<void> Function() onConfirm;

  const SmartGroupPreviewSheet({
    required this.onConfirm,
    super.key,
  });

  @override
  State<SmartGroupPreviewSheet> createState() => _SmartGroupPreviewSheetState();
}

class _SmartGroupPreviewSheetState extends State<SmartGroupPreviewSheet> {
  late final SmartGroupPreview _preview;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _preview = SmartGroupService.instance.preview();
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
      if (mounted) Get.back();
    } catch (e) {
      SmartDialog.showToast("分组失败：$e");
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          Flexible(
            child: SingleChildScrollView(
              padding: AppStyle.edgeInsetsA16.copyWith(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Remix.magic_line),
                      AppStyle.hGap8,
                      Text(
                        '按平台智能分组',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  AppStyle.vGap12,
                  Text(
                    '把 ${_preview.totalFollows} 位关注按平台归组；'
                    '一个主播可以同时属于多个分组，已有分组不会被改动。',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  AppStyle.vGap12,
                  for (final item in _preview.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            item.tagAlreadyExists
                                ? Remix.folder_3_line
                                : Remix.folder_add_line,
                            size: 18,
                            color: item.tagAlreadyExists
                                ? scheme.onSurfaceVariant
                                : scheme.primary,
                          ),
                          AppStyle.hGap8,
                          Text(item.siteName),
                          AppStyle.hGap8,
                          Text(
                            item.tagAlreadyExists ? '复用' : '新建',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${item.userCount} 位',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_preview.skippedUnknownSite > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '另有 ${_preview.skippedUnknownSite} 位所属平台已不在支持列表，跳过。',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA16.copyWith(top: 0, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Get.back(),
                  child: const Text('取消'),
                ),
                AppStyle.hGap8,
                FilledButton(
                  onPressed: _busy ? null : _run,
                  child: const Text('开始分组'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 打开预览确认。无可分组内容时只 toast，不弹一张空表。
Future<void> showSmartGroupPreview(Future<void> Function() onConfirm) async {
  final preview = SmartGroupService.instance.preview();
  if (preview.items.isEmpty) {
    SmartDialog.showToast('没有可分组的关注');
    return;
  }
  // 判「有没有活要干」要看**本次会新增的成员数**，不能只看「有没有新建组」：
  // 平台组可能早就存在但漏了后来新关注的人，那种情况照样要跑。
  if (preview.pendingTotal == 0) {
    SmartDialog.showToast('所有关注都已在对应平台分组里');
    return;
  }
  await Get.bottomSheet(
    SmartGroupPreviewSheet(onConfirm: onConfirm),
    backgroundColor: Get.theme.cardColor,
    isScrollControlled: true,
  );
}

/// 一键按平台分组：预览确认 → 执行归组 → 结果反馈。
///
/// 关注页顶栏 ⋮ 与关注设置页两个入口都走这份逻辑，行为完全一致：
/// * 无可分组内容时 [showSmartGroupPreview] 自己只 toast、不弹空表；
/// * 归组后发 `kUpdateFollow`，走既有链路刷新关注页与分组管理 sheet；
/// * [afterExecute] 给调用方补自己的收尾 —— 关注页那侧直接 `filterData()`
///   立即重切，设置页那侧靠上面那条事件链就够。
///
/// 为什么不写成 `FollowUserController.runSmartGrouping()` 让设置页去调：
/// 那个控制器 `onInit` 要 `vsync` 建 `TabController`，用户从未进过关注页时
/// 只能临时 `Get.put` 一份空壳实例，风险太大（计划「已知风险」第 1 条）。
Future<void> startSmartGrouping({void Function()? afterExecute}) async {
  await showSmartGroupPreview(() async {
    final result = await SmartGroupService.instance.execute();
    // 分组建/改完要走既有链路刷新关注页与分组管理 sheet。
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
    afterExecute?.call();
    if (result.didNothing) {
      SmartDialog.showToast('所有关注都已在对应平台分组里');
    } else {
      SmartDialog.showToast(
        '已新建 ${result.tagsCreated} 个分组，归组 ${result.membersAdded} 位主播',
      );
    }
  });
}
