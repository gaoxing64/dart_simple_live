import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils/permission_handler.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_menu.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class PlaySettingsPage extends GetView<AppSettingsController> {
  const PlaySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("直播间设置"),
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text(
              "播放器",
              style: context.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => SettingsSwitch(
                    title: "硬件解码",
                    value: controller.hardwareDecode.value,
                    subtitle: "播放失败可尝试关闭此选项",
                    onChanged: (e) {
                      controller.setHardwareDecode(e);
                    },
                  ),
                ),
                if (Platform.isAndroid) AppStyle.divider,
                Obx(
                  () => Visibility(
                    visible: Platform.isAndroid,
                    child: SettingsSwitch(
                      title: "兼容模式",
                      subtitle: "若播放卡顿可尝试打开此选项",
                      value: controller.playerCompatMode.value,
                      onChanged: (e) {
                        controller.setPlayerCompatMode(e);
                      },
                    ),
                  ),
                ),
                // AppStyle.divider,
                // Obx(
                //   () => SettingsNumber(
                //     title: "缓冲区大小",
                //     subtitle: "若播放卡顿可尝试调高此选项",
                //     value: controller.playerBufferSize.value,
                //     min: 32,
                //     max: 1024,
                //     step: 4,
                //     unit: "MB",
                //     onChanged: (e) {
                //       controller.setPlayerBufferSize(e);
                //     },
                //   ),
                // ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "系统媒体控制",
                    // 移动端这一项同时是「后台播放」：媒体通知就是前台服务的载体。
                    // 副标题按「自动暂停」分支——两者已不再互斥，开着自动暂停时
                    // 切后台就是会暂停，不能再承诺「继续播放」。
                    subtitle: Platform.isWindows ||
                            Platform.isLinux ||
                            Platform.isMacOS
                        ? "在系统媒体控件中显示播放控制与封面"
                        : controller.playerAutoPause.value
                            ? "在${Platform.isIOS ? "锁定屏幕与控制中心" : "通知栏与锁屏"}显示播放控制"
                            : "在${Platform.isIOS ? "锁定屏幕与控制中心" : "通知栏与锁屏"}显示播放控制，切到后台后继续播放",
                    value: controller.mediaControls.value,
                    onChanged: (e) {
                      onMediaControlsChanged(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "进入后台自动暂停",
                    subtitle: Platform.isAndroid || Platform.isIOS
                        ? "切到后台即暂停；开着媒体控制时仍可从通知栏继续播放"
                        : null,
                    value: controller.playerAutoPause.value,
                    onChanged: (e) {
                      controller.setPlayerAutoPause(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu<int>(
                    title: "画面尺寸",
                    value: controller.scaleMode.value,
                    valueMap: const {
                      0: "适应",
                      1: "拉伸",
                      2: "铺满",
                      3: "16:9",
                      4: "4:3",
                    },
                    onChanged: (e) {
                      controller.setScaleMode(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "使用HTTPS链接",
                    subtitle: "将http链接替换为https",
                    value: controller.playerForceHttps.value,
                    onChanged: (e) {
                      controller.setPlayerForceHttps(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                      title: "抖音HLS流优先",
                      subtitle: "hls流可缓解部分直播间抖动问题,重启后生效",
                      value: controller.douyinHlsFirst.value,
                      onChanged: (e) {
                        controller.setDouyinHlsFirst(e);
                      }),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                      title: "禁用滑动控制-音量/亮度",
                      value: controller.verticalDragLock.value,
                      onChanged: (e) {
                        controller.setVerticalDragLock(e);
                      }),
                ),
                AppStyle.divider,
                // 键盘控制的总开关、自定义开关与逐条改键都收进了独立页：这里十几行
                // 动作塞进播放设置会把整页撑得没法用，而且改键要弹录制框，本身就该
                // 有自己的家。
                SettingsAction(
                  title: "键盘控制",
                  subtitle: "总开关 / 自定义键位 / 恢复默认",
                  onTap: () => Get.toNamed(RoutePath.kSettingsShortcuts),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu<String>(
                    title: "Stats 覆盖层后端",
                    subtitle: "应用自绘可避免 mpv 内置 OSD 在 HDR 屏上引发的 1Hz 亮度闪烁，推荐保持默认",
                    value: controller.osdBackend.value,
                    valueMap: const {
                      "app": "应用自绘（推荐）",
                      "mpv": "mpv 内置 OSD",
                    },
                    onChanged: (e) {
                      controller.setOSDBackend(e);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "直播间",
              style: context.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => SettingsSwitch(
                    title: "进入直播间自动全屏",
                    value: controller.autoFullScreen.value,
                    onChanged: (e) {
                      controller.setAutoFullScreen(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => Visibility(
                    visible: Platform.isAndroid,
                    child: SettingsSwitch(
                      title: "进入小窗隐藏弹幕",
                      value: controller.pipHideDanmu.value,
                      onChanged: (e) {
                        controller.setPIPHideDanmu(e);
                      },
                    ),
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => Visibility(
                    visible: !(Platform.isAndroid || Platform.isIOS),
                    child: SettingsSwitch(
                      title: "小窗锁定画面比例",
                      value: controller.pipLockAspect.value,
                      onChanged: (e) {
                        controller.setPipLockAspect(e);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "清晰度",
              style: context.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              children: [
                Obx(
                  () => SettingsMenu<int>(
                    title: "默认清晰度",
                    value: controller.qualityLevel.value,
                    valueMap: const {
                      0: "最低",
                      1: "中等",
                      2: "最高",
                    },
                    onChanged: (e) {
                      controller.setQualityLevel(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu<int>(
                    title: "数据网络清晰度",
                    value: controller.qualityLevelCellular.value,
                    valueMap: const {
                      0: "最低",
                      1: "中等",
                      2: "最高",
                    },
                    onChanged: (e) {
                      controller.setQualityLevelCellular(e);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "聊天区",
              style: context.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => SettingsNumber(
                    title: "文字大小",
                    value: controller.chatTextSize.value.toInt(),
                    min: 8,
                    max: 36,
                    onChanged: (e) {
                      controller.setChatTextSize(e.toDouble());
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsNumber(
                    title: "上下间隔",
                    value: controller.chatTextGap.value.toInt(),
                    min: 0,
                    max: 12,
                    onChanged: (e) {
                      controller.setChatTextGap(e.toDouble());
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "气泡样式",
                    value: controller.chatBubbleStyle.value,
                    onChanged: (e) {
                      controller.setChatBubbleStyle(e);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 打开「系统媒体控制」时补一次通知权限（Android 13+ 缺它就看不见那条媒体通知）。
  ///
  /// 被拒不把开关打回去：播放与后台出声并不依赖通知权限（前台服务与音频焦点是
  /// 另一回事），缺的只是通知栏里那个控制入口。为此回滚开关反而让人以为没生效。
  Future<void> onMediaControlsChanged(bool e) async {
    controller.setMediaControls(e);
    if (!e || !Platform.isAndroid) {
      return;
    }
    try {
      final result = await Permission.notification.request();
      if (result.isPermanentlyDenied) {
        SmartDialog.showToast("通知权限已被拒绝，请在系统设置里为 Slive 打开通知");
      } else if (!result.isGranted) {
        SmartDialog.showToast("未授予通知权限：播放继续，但通知栏里没有控制入口");
      }
    } catch (error) {
      Log.logPrint(error);
    }
  }
}
