import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/follow_user/follow_info_setting/follow_info_controller.dart';
import 'package:simple_live_app/modules/follow_user/follow_info_setting/follow_profile_header.dart';
import 'package:simple_live_app/modules/follow_user/follow_info_setting/watch_heatmap.dart';
import 'package:simple_live_app/modules/follow_user/follow_info_setting/watch_year_selector.dart';
import 'package:simple_live_app/widgets/filter_button.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class FollowInfoPage extends GetView<FollowInfoController> {
  const FollowInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主播详情'),
        actions: [
          Obx(() {
            if (!controller.isFollowed.value) {
              return const SizedBox.shrink();
            }
            return controller.pageLoadding.value
                ? const IconButton(
                    tooltip: '刷新中',
                    onPressed: null,
                    icon: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: '刷新主播信息',
                    style: AppStyle.iconButtonStyle(Theme.of(context).colorScheme),
                    onPressed: controller.refreshData,
                    icon: const Icon(Icons.refresh),
                  );
          }),
          const SizedBox(width: 8),
        ],
      ),
      body: Obx(() {
        final follow = controller.followUser.value;
        if (follow == null) {
          return const Center(child: Text('未找到主播信息'));
        }
        final site = Sites.allSites[follow.siteId];
        if (site == null) {
          return const Center(child: Text('暂不支持此平台'));
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth < 600 ? 12.0 : 24.0;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FollowProfileHeader(
                        follow: follow,
                        site: site,
                        isFollowed: controller.isFollowed.value,
                      ),
                      AppStyle.vGap12,
                      _WatchStatsCard(controller: controller, follow: follow),
                      AppStyle.vGap12,
                      if (controller.isFollowed.value)
                        _FollowSettingsCard(controller: controller)
                      else
                        const _UnfollowedNoticeCard(),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: AppStyle.edgeInsetsA16,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppStyle.radius16,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              AppStyle.hGap8,
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          AppStyle.vGap12,
          child,
        ],
      ),
    );
  }
}

class _WatchStatsCard extends StatelessWidget {
  final FollowInfoController controller;
  final FollowUser follow;

  const _WatchStatsCard({required this.controller, required this.follow});

  @override
  Widget build(BuildContext context) {
    final History? history = controller.watchHistory.value;
    final year = controller.selectedWatchYear.value;
    final daily = history?.dailyWatchSeconds ?? const <String, int>{};
    final yearPrefix = '$year-';
    final yearDays = daily.entries.where((entry) => entry.key.startsWith(yearPrefix) && entry.value > 0);
    final yearSeconds = yearDays.fold<int>(0, (total, entry) => total + entry.value);
    final totalSeconds = history?.duration.inSeconds ?? follow.watchDurationSec;
    final recent = daily.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return _SectionCard(
      icon: Remix.bar_chart_box_line,
      title: '观看历史',
      trailing: WatchYearSelector(
        years: controller.watchYears,
        value: year,
        onChanged: (value) => controller.selectedWatchYear.value = value,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _StatItem(label: '累计观看', value: formatWatchSeconds(totalSeconds))),
              Expanded(child: _StatItem(label: '$year 年观看', value: formatWatchSeconds(yearSeconds))),
              Expanded(child: _StatItem(label: '$year 年观看天数', value: '${yearDays.length} 天')),
            ],
          ),
          AppStyle.vGap24,
          WatchHeatmap(year: year, dailyWatchSeconds: daily),
          AppStyle.vGap12,
          Text(
            '每日统计自支持此功能的版本开始记录，升级前的累计时长不会回填到具体日期。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          AppStyle.vGap12,
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          AppStyle.vGap12,
          Text('最近观看', style: Theme.of(context).textTheme.titleSmall),
          AppStyle.vGap8,
          if (recent.isEmpty)
            Text(
              '还没有每日观看记录',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          else
            for (final entry in recent.take(5)) _RecentWatchRow(entry: entry),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        AppStyle.vGap4,
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _RecentWatchRow extends StatelessWidget {
  final MapEntry<String, int> entry;

  const _RecentWatchRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(entry.key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(Remix.calendar_check_line, size: 18, color: Theme.of(context).colorScheme.primary),
          AppStyle.hGap8,
          Expanded(
            child: Text(
              date == null ? entry.key : '${date.year} 年 ${date.month} 月 ${date.day} 日',
            ),
          ),
          Text(formatWatchSeconds(entry.value)),
        ],
      ),
    );
  }
}

class _UnfollowedNoticeCard extends StatelessWidget {
  const _UnfollowedNoticeCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Remix.information_line,
      title: '尚未关注',
      child: Text(
        '关注该主播后，才能设置分组、备注，并在主播迁移平台时保留观看记录。',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _FollowSettingsCard extends StatelessWidget {
  final FollowInfoController controller;

  const _FollowSettingsCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Remix.settings_3_line,
      title: '关注设置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('所属分组', style: Theme.of(context).textTheme.bodyLarge),
          AppStyle.vGap8,
          Obx(() {
            final items = controller.tagOptions;
            if (items.isEmpty) {
              return const Text('还没有分组，可先在「关注设置 → 分组管理」中新建');
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in items)
                  FilterButton(
                    text: tag.tag,
                    selected: controller.checkedTags.contains(tag.tag),
                    onTap: () => controller.toggleTag(tag.tag),
                  ),
              ],
            );
          }),
          AppStyle.vGap12,
          Obx(
            () => ListTile(
              title: const Text('备注'),
              subtitle: Text(
                controller.followUser.value?.remark?.isNotEmpty == true
                    ? controller.followUser.value!.remark!
                    : '未设置',
              ),
              contentPadding: EdgeInsets.zero,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showRemarkDialog(context),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: Obx(() {
              final current = controller.followUser.value;
              final hasRemark = current?.remark?.isNotEmpty == true;
              return SettingsSwitch(
                key: const ValueKey('show-remark-as-name'),
                value: current?.showRemarkAsName ?? true,
                title: '显示为昵称',
                subtitle: hasRemark ? '使用备注替换主播原名' : '未设置备注时仍显示主播原名',
                onChanged: controller.setShowRemarkAsName,
              );
            }),
          ),
          Divider(height: 24, color: Theme.of(context).colorScheme.outlineVariant),
          Text('平台迁移', style: Theme.of(context).textTheme.bodyLarge),
          AppStyle.vGap4,
          Text(
            '主播更换平台或房间号时，保留关注、分组和观看记录。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          AppStyle.vGap12,
          TextField(
            controller: controller.migrationUrlController,
            decoration: const InputDecoration(
              hintText: '粘贴新平台的直播间链接',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => controller.parseAndMigrate(),
          ),
          AppStyle.vGap8,
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: controller.pasteFromClipboard,
                icon: const Icon(Remix.clipboard_line),
                label: const Text('粘贴链接'),
              ),
              FilledButton.icon(
                onPressed: controller.parseAndMigrate,
                icon: const Icon(Remix.arrow_right_line),
                label: const Text('解析并迁移'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRemarkDialog(BuildContext context) {
    final textController = TextEditingController(text: controller.followUser.value?.remark);
    Get.dialog(
      AlertDialog(
        title: const Text('修改备注'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '请输入备注名'),
          autofocus: true,
          onSubmitted: (value) {
            controller.updateRemark(value.trim());
            Get.back();
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              controller.updateRemark(textController.text.trim());
              Get.back();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(textController.dispose);
  }
}
