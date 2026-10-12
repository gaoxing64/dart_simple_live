import 'dart:io';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/account.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/sync_client_info_model.dart';
import 'package:simple_live_app/routes/live_room_route_args.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/sync_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// APP页面跳转封装
/// * 需要参数的页面都应使用此类
/// * 如不需要参数，可以使用Get.toNamed
class AppNavigator {
  /// 跳转至分类详情
  static void toCategoryDetail({required Site site, required LiveSubCategory category}) {
    Get.toNamed(RoutePath.kCategoryDetail, arguments: [site, category]);
  }

  /// 跳转至直播间
  ///
  /// [together] 是多开批量入口带进来的「另外几路」：会一次性预载成多开棋盘里的格子
  /// （第 0 格仍是 [site]/[roomId] 这一路）。旧调用点不必传。
  static void toLiveRoomDetail({
    required Site site,
    required String roomId,
    List<LiveRoomTarget> together = const [],
  }) async {
    if (site.id == Constant.kBiliBili &&
        !_biliBiliLogined() &&
        AppSettingsController.instance.bilibiliLoginTip.value) {
      var result = await Utils.showAlertDialog(
        "哔哩哔哩需要登录才能观看高清直播，是否前往登录？",
        title: "登录哔哩哔哩",
        actions: [
          TextButton(
            onPressed: () {
              AppSettingsController.instance.setBiliBiliLoginTip(false);
              Get.back(result: false);
            },
            child: const Text("不再提示"),
          ),
        ],
      );
      if (result == true) {
        await toBiliBiliLogin();
        if (!_biliBiliLogined()) {
          SmartDialog.showToast("未完成登录");
        }
      }
    }

    Get.toNamed(
      RoutePath.kLiveRoomDetail,
      arguments: LiveRoomRouteArgs(site: site, roomId: roomId, together: together),
    );
  }

  /// B 站是否已有激活账号。
  ///
  /// 账号体系迁移后旧的 `BiliBiliAccountService` 已移除，登录态统一从
  /// `DBService` 的 account 箱读取（siteId + isActive）。
  static bool _biliBiliLogined() {
    return DBService.instance.getAllAccounts().any(
          (account) => account.siteId == Constant.kBiliBili && account.isActive,
        );
  }

  static Future toQRCoreLogin({required Account account}) async {
    Get.toNamed(RoutePath.kAccountQRLogin, arguments: account);
  }

  /// 跳转至哔哩哔哩网页登录
  static Future toBiliBiliWebLogin({required Account account}) async {
    Get.toNamed(RoutePath.kBiliBiliWebLogin, arguments: account);
  }

  /// 跳转至哔哩哔哩登录
  static Future toBiliBiliLogin() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await Get.toNamed(RoutePath.kBiliBiliWebLogin);
    } else {
      await Get.toNamed(RoutePath.kBiliBiliQRLogin);
    }
  }

  /// 跳转至同步设备
  static Future toSyncDevice(SyncClinet client, SyncClientInfoModel info) async {
    await Get.toNamed(
      RoutePath.kLocalSyncDevice,
      arguments: {
        "client": client,
        "info": info,
      },
    );
  }

  /// 跳转至关注用户信息详情
  static void toFollowInfo(FollowUser follow) {
    Get.toNamed(RoutePath.kFollowInfo, arguments: follow);
  }
}
