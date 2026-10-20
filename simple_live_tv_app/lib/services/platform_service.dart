import 'dart:async';
import 'dart:convert';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/models/db/account.dart';
import 'package:simple_live_tv_app/services/db_service.dart';

class PlatformService extends GetxService {
  static PlatformService get instance => Get.find<PlatformService>();

  RxList<Account> accountList = RxList();

  void initAccount() {
    accountList.value = DBService.instance.getAllAccounts();
    // 自动更新
    for (var account in accountList) {
      accountLogin(account);
    }
  }

  // 更新指定的站点账户数据
  Future<void> updateAccount(Account ac) async {
    accountList.assignAll(
      accountList.map((a) => a.id == ac.id ? ac : a).toList(),
    );
    accountList.refresh();
    await DBService.instance.addAccount(ac);
  }

  Future<void> accountLogout(Account ac) async {
    var logout = ac.copyWith(
      id: ac.id,
      userName: '',
      credential: '',
      isActive: false,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await updateAccount(logout);
  }

  Future<bool> accountLogin(Account ac) async {
    var site = Sites.allSites[ac.siteId]!;
    AccountInfo info = await site.liveSite.getAccountInfo(credential: ac.credential);
    // core 在校验失败时可能回传空 credential，不能拿它覆盖用户已保存的凭证 ——
    // 一次偶发失败就会把登录态从账号库里抹掉，之后每次开机都判失效。
    var credential = info.credential.isNotEmpty ? info.credential : ac.credential;
    var resAc = ac.copyWith(
      userName: info.name,
      avatar: info.avatar,
      uid: info.uid,
      credential: credential,
      isActive: info.isValid,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await updateAccount(resAc);
    site.liveSite.setSiteAttrs(resAc.credential);
    // 从未登录（空 credential / 空 cookie）不是「失效」，不弹提示；
    // 只有配了凭证却校验不过才需要用户重新设置。
    if (!info.isValid && _hasConfiguredCookie(ac.credential)) {
      SmartDialog.showToast('${site.name}账号失效，请重新设置');
    }
    return info.isValid;
  }

  /// credential 里有没有可校验的 cookie。
  /// 迁移种子或从未登录的账号行会带空串 / `{"cookie":""}`，那是「未登录」而不是
  /// 「账号失效」—— 启动校验每次都弹提示就是这么来的。
  static bool _hasConfiguredCookie(String credential) {
    if (credential.trim().isEmpty) {
      return false;
    }
    try {
      var decoded = jsonDecode(credential);
      if (decoded is Map) {
        var cookie = decoded['cookie'];
        return cookie is String && cookie.isNotEmpty;
      }
    } catch (_) {
      // 非 JSON 的老格式按已配置处理
    }
    return true;
  }

  @override
  void onInit() {
    initAccount();
    super.onInit();
  }
}
