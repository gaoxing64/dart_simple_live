import 'package:material_ui/material_ui.dart';
import 'package:remixicon/remixicon.dart';

class Constant {
  static const String kUpdateFollow = "UpdateFollow";
  static const String kUpdateHistory = "UpdateHistory";
  static const String kUpdateDanmaku = "UpdateDanmaku";
  static const String kUpdateAccount = "UpdateAccount";

  static final Map<String, HomePageItem> allHomePages = {
    "recommend": HomePageItem(
      iconData: Remix.home_smile_line,
      title: "首页",
      index: 0,
    ),
    "follow": HomePageItem(
      iconData: Remix.heart_line,
      title: "关注",
      index: 1,
    ),
    "category": HomePageItem(
      iconData: Remix.apps_line,
      title: "分类",
      index: 2,
    ),
    "user": HomePageItem(
      iconData: Remix.user_smile_line,
      title: "我的",
      index: 3,
    ),
  };

  static const String kBiliBili = "bilibili";

  /// B站是否走 Rust Core（D2 集成开关；构建体验版暂置 true —— 上手验证 Rust 路径；
  /// 出问题改回 false 即回退 Dart core。稳定后按 J-9 判据定稿默认值）
  static const bool kUseRustBilibili = true;
  /// 斗鱼/虎牙/抖音/Twitch 是否走 Rust Core（IP-3~6）。
  /// 四平台离线测试已全绿（898 passed / 0 failed）+ App 回归零新增失败
  /// → 构建体验版翻 true 供真机验证；出问题改回 false 即回退 Dart core（AC-31）。
  static const bool kUseRustDouyu = true;
  static const bool kUseRustHuya = true;
  static const bool kUseRustDouyin = true;
  static const bool kUseRustTwitch = true;
  static const String kDouyu = "douyu";
  static const String kHuya = "huya";
  static const String kDouyin = "douyin";
  static const String kTwitch = "twitch";
}

class HomePageItem {
  final IconData iconData;
  final String title;
  final int index;
  HomePageItem({
    required this.iconData,
    required this.title,
    required this.index,
  });
}

enum DownloadState {
  notDownloaded,
  downloading,
  downloaded,
}

// 排序方法
enum SortMethod {
  watchDuration,
  siteId,
  recently,
  userNameASC,
  userNameDESC,
  tag,
}

extension SortMethodStore on SortMethod {
  String get storeValue => name;
  static SortMethod fromStore(String? v) {
    if (v == null) return SortMethod.watchDuration;
    return SortMethod.values.firstWhere(
      (e) => e.name == v,
      orElse: () => SortMethod.watchDuration,
    );
  }
}
