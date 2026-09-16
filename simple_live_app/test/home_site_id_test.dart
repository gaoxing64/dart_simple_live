// 首页 tab → 平台 id 的映射单测（纯逻辑，不依赖 widget）。
//
// 这是「首页把当前平台带给搜索页」这条链路上唯一的映射点，
// 写错了表现是搜索页停在了别的平台；越界保护只在内存里，崩了也是静默的。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';

/// 跳过本地存储（Hive 在 widget test 的 fake-async 环境下不可用），
// `supportSites` 读的是 `siteSort`，这里给一份全平台顺序。
class _FakeSettings extends AppSettingsController {
  _FakeSettings() {
    siteSort.value = Sites.allSites.keys.toList();
  }

  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_FakeSettings());
  });

  tearDown(() => Get.reset());

  test('下标合法时返回对应平台 id', () {
    final sites = Sites.supportSites;
    expect(sites.length, greaterThan(0));

    for (var i = 0; i < sites.length; i++) {
      expect(siteIdAtHomeTab(i), sites[i].id);
    }
  });

  test('下标越界返回 null 而不是抛 RangeError', () {
    final len = Sites.supportSites.length;

    // refreshOrScrollTop / toSearch 都可能拿到越界下标
    // （TabController 还没 attach、或平台列表刚变化但 tab 数没同步），
    // 这里必须返回 null 让调用方跳过，不能崩。
    expect(siteIdAtHomeTab(-1), isNull);
    expect(siteIdAtHomeTab(len), isNull);
    expect(siteIdAtHomeTab(len + 100), isNull);
  });

  test('返回值与当前平台列表同步：排序变化后下标含义跟着变', () {
    // 「网站排序」设置会改 supportSites 的顺序，下标 → id 的映射必须
    // 每次实时读列表，缓存住就会在改顺序后指向错误平台。
    final first = Sites.supportSites.first.id;
    expect(siteIdAtHomeTab(0), first);
  });
}
