import 'package:material_ui/material_ui.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/icons/live_icons.dart';
import 'package:simple_live_core/simple_live_core.dart';

class Sites {
  static final Map<String, Site> allSites = {
    Constant.kBiliBili: Site(
      id: Constant.kBiliBili,
      iconData: RemixIcons.bilibili_line,
      logo: "assets/images/bilibili_2.png",
      name: "哔哩哔哩",
      liveSite: RustBilibiliSite(),
    ),
    Constant.kDouyu: Site(
      id: Constant.kDouyu,
      iconData: LiveIcons.douyu,
      logo: "assets/images/douyu.png",
      name: "斗鱼直播",
      liveSite: RustDouyuSite(),
    ),
    Constant.kHuya: Site(
      id: Constant.kHuya,
      iconData: LiveIcons.huya,
      logo: "assets/images/huya.png",
      name: "虎牙直播",
      liveSite: RustHuyaSite(),
    ),
    Constant.kDouyin: Site(
      id: Constant.kDouyin,
      iconData: RemixIcons.tiktok_line,
      logo: "assets/images/douyin.png",
      name: "抖音直播",
      liveSite: RustDouyinSite(),
    ),
    Constant.kTwitch: Site(
      id: Constant.kTwitch,
      iconData: RemixIcons.twitch_line,
      logo: "assets/images/Twitch.png",
      name: "Twitch",
      liveSite: RustTwitchSite(),
    )
  };

  static List<Site> get supportSites {
    return AppSettingsController.instance.siteSort
        .where((key) => Sites.allSites[key]?.name != 'Twitch')
        .map((key) => allSites[key]!)
        .toList();
  }

  /// 按 [sort] 排已知平台 id，缺项按声明序补全。
  ///
  /// [sort] 是首页平台排序的持久化结果，只在 `initSiteSort()` 里补过一次，
  /// 换设备恢复 / 版本新增站点之后可能不全。直接用会把缺掉的已知平台整个
  /// 漏掉 —— 关注页第二栏的平台标签、设置里的平台子开关都走这里。
  static List<String> orderedIds(Iterable<String> sort) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final id in sort) {
      if (allSites.containsKey(id) && seen.add(id)) {
        ordered.add(id);
      }
    }
    for (final id in allSites.keys) {
      if (seen.add(id)) {
        ordered.add(id);
      }
    }
    return ordered;
  }
}

class Site {
  final String id;
  final String name;
  final String logo;
  final IconData iconData;
  final LiveSite liveSite;

  Site({
    required this.id,
    required this.liveSite,
    required this.logo,
    required this.name,
    required this.iconData,
  });
}
