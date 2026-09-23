import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/ui/secondary_tap_region.dart';

/// 分组管理：关注设置页与关注页顶栏共用同一个 bottom sheet。
///
/// 原先这套逻辑长在 `FollowAppSettingsController` 里，而那个控制器只由
/// 设置页路由注册，关注页拿不到；提取成共享类后两个入口行为完全一致。
///
/// 所有变更最终都走 FollowService + `kUpdateFollow` 事件 —— 这是刷新关注页
/// 列表的既有链路（FollowService 重载 → updatedListStream →
/// FollowUserController.updateTagList + filterData）。
///
/// 用户可见文案统一叫「分组」；代码标识符（tag/FollowUserTag）沿用历史命名。
class FollowTagManagerController extends BaseController {
  // 用户自定义分组
  RxList<FollowUserTag> userTagList = <FollowUserTag>[].obs;

  /// 共享实例：顶栏开 sheet、卡片头部长按改名都复用同一份状态。
  static FollowTagManagerController get shared =>
      Get.isRegistered<FollowTagManagerController>()
          ? Get.find<FollowTagManagerController>()
          : Get.put(FollowTagManagerController());

  @override
  void onInit() {
    updateTagList();
    super.onInit();
  }

  // 分组管理
  void updateTagList() {
    userTagList.assignAll(FollowService.instance.followTagList);
    // 修改tag 通知 follo_user_controller 数据更新
    EventBus.instance.emit(Constant.kUpdateFollow, 0);
  }

  Future removeTag(FollowUserTag tag) async {
    await FollowService.instance.removeFollowUserTag(tag);
    updateTagList();
    Log.i('删除tag${tag.tag}');
  }

  void addTag(String tag) async {
    // 内置标签名是保留字：分组按名字分桶、「全部」是哨兵，撞名会让界面与语义打架
    if (FollowUserController.isReservedTagName(tag)) {
      SmartDialog.showToast("「$tag」是内置分组名，不能占用");
      return;
    }
    await FollowService.instance.addFollowUserTag(tag);
    updateTagList();
  }

  Future<void> updateTag(FollowUserTag followUserTag) async {
    await FollowService.instance.updateFollowUserTag(followUserTag);
  }

  void updateTagName(FollowUserTag followUserTag, String newTagName) {
    // 未操作
    if (followUserTag.tag == newTagName) {
      return;
    }
    // 内置标签名是保留字
    if (FollowUserController.isReservedTagName(newTagName)) {
      SmartDialog.showToast("「$newTagName」是内置分组名，不能占用");
      return;
    }
    // 避免重名
    if (userTagList.any((item) => item.tag == newTagName)) {
      SmartDialog.showToast("分组名重复，修改失败");
      return;
    }
    FollowService.instance.updateTagName(followUserTag, newTagName);
    SmartDialog.showToast("分组名修改成功");
    updateTagList();
  }

  void updateTagOrder(int oldIndex, int newIndex) {
    FollowService.instance.reorderFollowTag(oldIndex, newIndex);
    updateTagList();
  }

  // 分组管理弹窗
  void showTagsManager() {
    Utils.showBottomSheet(
      title: '分组管理',
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppStyle.divider,
            ListTile(
              title: const Text("新建分组"),
              leading: const Icon(Icons.add),
              onTap: () {
                editTagDialog("新建分组");
              },
            ),
            AppStyle.divider,
            // 列表内容
            Expanded(
              child: Obx(
                () => ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: userTagList.length,
                  itemBuilder: (context, index) {
                    // 偏移
                    FollowUserTag item = userTagList[index];
                    return ListTile(
                      key: ValueKey(item.id),
                      title: SecondaryTapRegion(
                        onSecondaryTap: () => editTagDialog("重命名分组",
                            followUserTag: item),
                        child: GestureDetector(
                          child: Text(item.tag),
                          onLongPress: () {
                            editTagDialog("重命名分组", followUserTag: item);
                          },
                        ),
                      ),
                      leading: IconButton(
                        tooltip: "删除分组",
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          removeTag(item);
                        },
                      ),
                      // 用即时拖动而不是 Delayed：拖动目标是右侧这个小手柄，
                      // 不存在与列表滚动抢手势的问题，按住 500ms 才可拖
                      // 在桌面端纯属负担（触屏上直接按住手柄拖动也更顺手）。
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    );
                  },
                  onReorderItem: (int oldIndex, int newIndex) {
                    updateTagOrder(oldIndex, newIndex);
                  },
                ),
              ),
            ),
          ]),
    );
  }

  void editTagDialog(String title, {FollowUserTag? followUserTag}) {
    final TextEditingController tagEditController =
        TextEditingController(text: followUserTag?.tag);
    bool upMode = title == "新建分组" ? true : false;
    Get.dialog(
      AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        // 这里**不**按 `viewInsets.bottom` 垫底部内边距：对话框路由本身已经把
        // AlertDialog 摆在键盘上方了，再垫一次等于把键盘高度算两遍 —— 搜索态
        // （键盘抬起）下长按分组弹重命名，面板会被撑到几乎占满键盘上方整屏。
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                ),
              ),
              TextField(
                controller: tagEditController,
                minLines: 1,
                maxLines: 1,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding: AppStyle.edgeInsetsA12,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.grey.withValues(
                        alpha: .2,
                      ),
                    ),
                  ),
                ),
                onSubmitted: (tag) {
                  upMode
                      ? addTag(tagEditController.text)
                      : updateTagName(followUserTag!, tagEditController.text);
                  Get.back();
                },
              ),
              SizedBox(
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Get.back();
                      },
                      child: const Text('否'),
                    ),
                    TextButton(
                      onPressed: () {
                        upMode
                            ? addTag(tagEditController.text)
                            : updateTagName(
                                followUserTag!,
                                tagEditController.text,
                              );
                        Get.back();
                      },
                      child: const Text('是'),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

/// 打开分组管理 bottom sheet（关注页顶栏 / 关注设置页共用入口）。
void showFollowTagManagerSheet() =>
    FollowTagManagerController.shared.showTagsManager();
