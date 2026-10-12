import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/follow_user/follow_info_setting/follow_info_controller.dart';
import 'package:simple_live_app/widgets/filter_button.dart';

class FollowInfoPage extends GetView<FollowInfoController> {
  const FollowInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final site = Sites.allSites[controller.followUser.value!.siteId]!;
    return Scaffold(
      appBar: AppBar(
        title: const Text("关注信息设置"),
        actions: [
          Obx(
            () => controller.pageLoadding.value
                ? const IconButton(
                    tooltip: "刷新中",
                    onPressed: null,
                    icon: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: "刷新",
                    onPressed: () {
                      controller.refreshData();
                    },
                    icon: const Icon(Icons.refresh),
                  ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部：头像+平台+房间号
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Obx(
              () => Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(controller.followUser.value!.face),
                  ),
                  AppStyle.hGap12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.followUser.value!.remark?.isNotEmpty == true
                              ? '${controller.followUser.value!.userName} (${controller.followUser.value!.remark!})'
                              : controller.followUser.value!.userName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        AppStyle.vGap4,
                        Row(
                          children: [
                            Image.asset(site.logo, width: 18),
                            AppStyle.hGap8,
                            Flexible(
                              child: Text(
                                '${site.name}  房间号：${controller.followUser.value!.roomId}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: .7),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          AppStyle.divider,
          // 分组设置：多归属 = 多选 chips（勾选 = 加入该分组，取消 = 移出该分组）
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Obx(() {
              final items = controller.tagOptions;
              if (items.isEmpty) {
                return const Text('还没有分组，先去「关注设置 → 分组管理」新建');
              }
              return Row(
                children: [
                  Text('所属分组', style: Theme.of(context).textTheme.bodyLarge),
                  AppStyle.hGap12,
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in items)
                          FilterButton(
                            text: t.tag,
                            selected: controller.checkedTags.contains(t.tag),
                            onTap: () => controller.toggleTag(t.tag),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
          AppStyle.divider,
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Obx(() {
              return ListTile(
                title: Text('备注设置', style: Theme.of(context).textTheme.bodyLarge),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: AppStyle.radius8,
                ),
                contentPadding: AppStyle.edgeInsetsL16.copyWith(right: 8),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      controller.followUser.value?.remark?.isNotEmpty == true
                          ? controller.followUser.value!.remark!
                          : '无',
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.grey),
                    ),
                    AppStyle.hGap4,
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                  ],
                ),
                onTap: () {
                  final textController = TextEditingController(text: controller.followUser.value?.remark);
                  Get.dialog(
                    AlertDialog(
                      title: const Text("修改备注"),
                      content: TextField(
                        controller: textController,
                        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "请输入备注名"),
                        autofocus: true,
                        onSubmitted: (value) {
                          controller.updateRemark(value.trim());
                          Get.back();
                        },
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(),
                          child: const Text("取消"),
                        ),
                        TextButton(
                          onPressed: () {
                            controller.updateRemark(textController.text.trim());
                            Get.back();
                          },
                          child: const Text("确定"),
                        ),
                      ],
                    ),
                  );
                },
              );
            }),
          ),
          AppStyle.divider,
          // 平台迁移：输入链接解析
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Remix.link),
                    SizedBox(width: 8),
                    Text('平台迁移（输入直播链接进行解析）'),
                  ],
                ),
                AppStyle.vGap8,
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller.migrationUrlController,
                        decoration: const InputDecoration(
                          hintText: '粘贴主播在新平台的直播间链接，如 https://... ',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => controller.parseAndMigrate(),
                      ),
                    ),
                    AppStyle.vGap8,
                    IconButton(
                      tooltip: '粘贴',
                      onPressed: controller.pasteFromClipboard,
                      icon: const Icon(Remix.clipboard_line),
                    ),
                    ElevatedButton.icon(
                      onPressed: controller.parseAndMigrate,
                      icon: const Icon(Remix.arrow_right_line),
                      label: const Text('迁移'),
                    ),
                  ],
                ),
                AppStyle.vGap12,
                Text(
                  "other todo ...",
                  style: TextStyle(color: Colors.grey),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
