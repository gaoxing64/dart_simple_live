import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/signalr_service.dart';
import 'package:url_launcher/url_launcher_string.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light.copyWith(
              systemNavigationBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              systemNavigationBarColor: Colors.transparent,
            ),
      child: SafeArea(
        // bottom: false：悬浮导航栏模式下内容需延伸到胶囊下方，
        // 底部避让由 ListView 的 padding 中的 MediaQuery bottom 处理
        bottom: false,
        child: ListView(
          padding: AppStyle.edgeInsetsA4.copyWith(
            bottom: MediaQuery.paddingOf(context).bottom + 4,
          ),
          children: [
            AppStyle.vGap12,
            ListTile(
              leading: Image.asset(
                'assets/images/logo.png',
                width: 56,
                height: 56,
              ),
              title: Text(
                "Slive",
                style: TextStyle(
                  height: 1.0,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: const _TileText("我就默默看你表演", dim: true),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.dialog(AboutDialog(
                  applicationIcon: Image.asset(
                    'assets/images/logo.png',
                    width: 48,
                    height: 48,
                  ),
                  applicationName: "Slive",
                  applicationVersion: "我就默默看你表演",
                  applicationLegalese: "Ver ${Utils.packageInfo.version}",
                ));
              },
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            _buildCard(
              children: [
                ListTile(
                  leading: const Icon(Remix.history_line),
                  title: const _TileText("观看记录"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kHistory);
                  },
                ),
              ],
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            ListTile(
              leading: const Icon(Remix.account_circle_line),
              title: const _TileText("账号管理"),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Get.toNamed(RoutePath.kSettingsAccount);
              },
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            ListTile(
              leading: const Icon(Icons.devices),
              title: const _TileText("数据同步"),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Get.toNamed(RoutePath.kSync);
              },
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            ListTile(
              leading: const Icon(Remix.link),
              title: const _TileText("链接解析"),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Get.toNamed(RoutePath.kTools);
              },
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            _buildCard(
              children: [
                ListTile(
                  leading: const Icon(Remix.moon_line),
                  title: const _TileText("外观设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kAppstyleSetting);
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.home_2_line),
                  title: const _TileText("主页设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsIndexed);
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.play_circle_line),
                  title: const _TileText("直播设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsPlay);
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.text),
                  title: const _TileText("弹幕设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsDanmu);
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.timer_2_line),
                  title: const _TileText("定时关闭"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsAutoExit);
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.apps_line),
                  title: const _TileText("其他设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsOther);
                  },
                ),
                if (kDebugMode)
                  ListTile(
                    leading: const Icon(Remix.apps_line),
                    title: const _TileText("测试"),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () async {
                      SignalRService signalRService = SignalRService();
                      await signalRService.connect();
                      //Get.toNamed(RoutePath.kTest);
                      var room = await signalRService.createRoom();
                      Log.logPrint(room);
                    },
                  ),
              ],
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            _buildCard(
              children: [
                const ListTile(
                  leading: Icon(Remix.error_warning_line),
                  title: _TileText("免责声明"),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: Utils.showStatement,
                ),
                ListTile(
                  leading: const Icon(Remix.github_line),
                  title: const _TileText("开源主页"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    launchUrlString(
                      "https://github.com/slotsun/dart_simple_live",
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.upload_2_line),
                  title: const _TileText("检查更新"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TileText("Ver ${Utils.packageInfo.version}", dim: true),
                      AppStyle.hGap4,
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                  onTap: () {
                    Utils.checkUpdate(showMsg: true);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    // 列表项圆角已提到全局主题（`AppStyle.light/darkTheme` 的 `listTileTheme`），
    // 原来这里单独套一层 Theme 只罩住了本页的部分行，导致同一页里
    // 「一部分圆角、一部分直角」（用户报过）。现在统一由主题负责。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// 列表项文字：显式带上当前主题色。
///
/// 为什么不直接用裸 `Text`：`ListTile` 会把标题/副标题的颜色包进一个
/// `AnimatedDefaultTextStyle(duration: kThemeChangeDuration = 200ms)`。
/// 被上层路由覆盖的页面在 Overlay 里处于 offstage，其 `TickerMode` 被关闭，
/// 这段主题色动画会被冻在旧配色上，等页面回到前台时才补播 —— 表现为
/// 「从外观设置返回后，文字要卡一下才跟上」。
/// 这里直接给出最终颜色，文字就不参与该动画，任何时刻重建都是正确配色。
class _TileText extends StatelessWidget {
  const _TileText(this.text, {this.dim = false});

  final String text;

  /// true 用 `onSurfaceVariant`（副标题、尾部说明文字），
  /// false 用 `onSurface`（标题）。与 `ListTile` 自身的取色保持一致。
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        color: dim ? scheme.onSurfaceVariant : scheme.onSurface,
      ),
    );
  }
}
