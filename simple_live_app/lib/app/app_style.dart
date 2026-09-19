import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/system_ui_inset.dart';

class AppColors {
  static ColorScheme lightColorScheme = ColorScheme.fromSeed(
    // primarySwatch: Colors.blue,
    seedColor: const Color(0xff3498db),
    brightness: Brightness.light,
  );
  static ColorScheme darkColorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff3498db),
    brightness: Brightness.dark,
  );

  static const Color black333 = Color(0xFF333333);
}

class AppStyle {
  static ThemeData light({String? fontFamily}) {
    return ThemeData(
      colorScheme: AppColors.lightColorScheme,
      useMaterial3: true,
      fontFamily: fontFamily,
      visualDensity: VisualDensity.standard,
      // ⚠️ **全局统一列表项的圆角**。
      //
      // 以前只有 `SettingsMenu` 自己设了 `shape`、`mine_page` 里只有被
      // `_buildCard` 罩住的行才有，于是同一个页面里「一部分圆角、一部分直角」，
      // 用户报过。`ListTile` 会把 `shape` 传给 `InkWell.customBorder`
      // （见 `material/list_tile.dart:982`），所以设在这里
      // **hover / 按压高亮的圆角也跟着一起统一**。
      //
      // 注意：只对 `ListTile` 生效。自己拼的 `InkWell`（例如关注页下段的
      // `_OfflineRow`）仍要显式给 `borderRadius`。
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppStyle.radius8),
      ),
      // 弹出菜单（`PopupMenuButton`）换成 M3 Expressive 的大圆角容器。
      //
      // MD3 baseline 是 **4dp**（`_PopupMenuDefaultsM3.shape`，等于形状刻度里的
      // extraSmall）；M3 Expressive 把菜单容器改成了圆角。这里取形状刻度里的
      // **large = 16dp**（刻度：none 0 / extraSmall 4 / small 8 / medium 12 /
      // large 16 / extraLarge 28 / full 50%）。
      //
      // 放在主题里统一给 ⇒ 全 App 的弹出菜单一起变，避免又出现「一处圆一处方」。
      // 注意这里只改**容器**圆角；菜单项的 hover 高亮形状 `PopupMenuItem` 里
      // 不可配（内部是裸 `InkWell`），已用 `AppPopupMenuItem` 自己实现
      // 「内缩 8dp + 同刻度大圆角」——写新菜单时请一律用它，别用官方那个。
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppStyle.radius16),
      ),
      appBarTheme: AppBarTheme(
        //elevation: 0,
        centerTitle: true,
        // ⚠️ 钉住 AppBar 的外观。
        //
        // M3 默认会在「内容滚到 AppBar 下方」时（`WidgetState.scrolledUnder`）
        // 把背景从 `colorScheme.surface` 换成 `colorScheme.surfaceContainer`，
        // 还会叠一层 `surfaceTint` 高度着色。实测：滚动前 `(249,249,255)`、
        // 滚动后 `(224,226,236)` —— 而搜索框的 `filled` 填充色是 `(226,226,233)`，
        // 两者几乎一模一样 ⇒ 一滚动 AppBar 就和搜索框撞色，很丑（用户报过，深浅色都有）。
        //
        // 显式给出 `backgroundColor` 之后，`scrolledUnder` 前后会解析到**同一个值**
        // （见 `app_bar.dart` 里 `_resolveColor(states, …, surfaceContainer)` 那段：
        // 只要主题里设了 backgroundColor，滚动态用的也是同一个值），
        // 再关掉高度着色与滚动态高度，外观就完全稳定了。
        //
        // ⚠️ 这里的值只对**默认主题色**准确：`main.dart` 会用
        // `.copyWith(colorScheme: …)` 换成用户自选主题色 / 动态取色的调色板，
        // 所以 main.dart 还会同步覆盖这里的 backgroundColor，否则改主题色后
        // AppBar 会和页面底色出现色差。
        backgroundColor: AppColors.lightColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          color: AppColors.black333,
        ),
        foregroundColor: AppColors.black333,
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          systemNavigationBarColor: Colors.transparent,
        ),
      ),
    );
  }

  static ThemeData darkTheme({String? fontFamily}) {
    return ThemeData.dark().copyWith(
      colorScheme: AppColors.darkColorScheme,
      visualDensity: VisualDensity.standard,
      // 同浅色主题：全局统一列表项圆角，顺带统一 hover 高亮的圆角。
      // 详见 `light()` 里的说明。
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppStyle.radius8),
      ),
      // 同浅色主题：弹出菜单统一用 M3 Expressive 的大圆角容器（16dp）。
      // 不这么写深浅两套就会不一致 —— 详见 `light()` 里的说明。
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppStyle.radius16),
      ),
      textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: fontFamily,
          ),
      primaryTextTheme: ThemeData().textTheme.apply(
            fontFamily: fontFamily,
          ),
      appBarTheme: AppBarTheme(
        //elevation: 0,

        centerTitle: true,
        // 同浅色主题：钉住外观，避免滚到内容下方时背景从 surface 变成
        // surfaceContainer、和搜索框填充色撞在一起。详见 `light()` 里的说明
        // （同样会被 main.dart 按实际生效的 colorScheme 覆盖）。
        backgroundColor: AppColors.darkColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          color: Colors.white,
        ),
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          systemNavigationBarColor: Colors.transparent,
        ),
      ),
      // radioTheme: RadioThemeData(
      //   fillColor: MaterialStateProperty.all(AppColors.darkColorScheme.primary),
      // ),
      // checkboxTheme: CheckboxThemeData(
      //   fillColor: MaterialStateProperty.all(AppColors.darkColorScheme.primary),
      // ),
      // tabBarTheme: TabBarTheme(
      //   labelColor: AppColors.darkColorScheme.primary,
      //   unselectedLabelColor: Colors.white70,
      //   indicator: RectangularIndicator(
      //     color: Colors.white.withAlpha(50),
      //     topLeftRadius: 24,
      //     bottomLeftRadius: 24,
      //     topRightRadius: 24,
      //     bottomRightRadius: 24,
      //     verticalPadding: 8,
      //     horizontalPadding: 0,
      //   ),
      // ),
    );
  }

  /// 圆形图标按钮的统一直径。
  ///
  /// 指的是**高亮 / 水波纹圆的尺寸**，不是点击热区 —— 热区仍由
  /// `MaterialTapTargetSize.padded` 撑到 48dp（视觉 40、热区 48，和 M3 一致）。
  /// 要整体调大调小只改这一个数。
  static const double kIconButtonSize = 40;

  /// 圆形图标按钮的统一规格：形状、尺寸、hover / 按压 / 聚焦反馈完全一致。
  ///
  /// **为什么必须显式传给按钮、不能只靠 `ThemeData.iconButtonTheme`**：
  /// `AppBar` 在 M3 下会**重建** leading / actions 的 `IconButtonTheme`
  /// （`material/app_bar.dart:1019-1046`、`:1119-1138`）。本项目设了
  /// `appBarTheme.foregroundColor` 与 `titleTextStyle.color`，于是
  /// `overallIconTheme != defaults.iconTheme` 恒成立 ⇒ 它走 else 分支，用
  /// `IconButton.styleFrom(foregroundColor: …)` **把 overlayColor 覆盖掉**。
  /// 所以只改主题里的 overlay 对顶栏按钮无效，必须显式给按钮传 `style:`。
  /// （`PopupMenuButton` 内部会把 `style` 透传给它的 `IconButton`，同样吃得进去。）
  ///
  /// ⚠️ **第二个坑**：别再给单个按钮叠
  /// `visualDensity: VisualDensity.compact` + `padding: EdgeInsets.zero`
  /// + `constraints: BoxConstraints()` 这套压缩组合 —— 它会把高亮压到
  /// **16dp**（`compact` 在 24dp 图标上又减 8），关注页下段行尾的取关按钮
  /// 曾经就是这样，几乎看不见。要更紧凑请改 [kIconButtonSize]。
  static ButtonStyle iconButtonStyle(ColorScheme scheme) => ButtonStyle(
        shape: const WidgetStatePropertyAll(CircleBorder()),
        minimumSize: const WidgetStatePropertyAll(
          Size.square(kIconButtonSize),
        ),
        // padding 归零：尺寸完全由 minimumSize 决定，图标在 40dp 里居中
        // （24dp 图标四周各 8dp）。保留默认的 `all(8)` 会让「40 = 24+8+8」
        // 与 minimumSize 两套算法互相打架，改图标尺寸时行为就漂了。
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        // 显式钉住密度，免得某个祖先的 compact density 把尺寸又缩回去。
        visualDensity: VisualDensity.standard,
        // 与 M3 标准 IconButton 严格一致（`_IconButtonDefaultsM3.overlayColor`）：
        // hover 8%、pressed / focused 10%，颜色取 `onSurfaceVariant`。
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)) {
            return scheme.onSurfaceVariant.withValues(alpha: 0.1);
          }
          if (states.contains(WidgetState.hovered)) {
            return scheme.onSurfaceVariant.withValues(alpha: 0.08);
          }
          return null;
        }),
      );

  static const vGap4 = SizedBox(
    height: 4,
  );
  static const vGap8 = SizedBox(
    height: 8,
  );
  static const vGap12 = SizedBox(
    height: 12,
  );
  static const vGap24 = SizedBox(
    height: 24,
  );
  static const vGap32 = SizedBox(
    height: 32,
  );
  static const vGap48 = SizedBox(
    height: 48,
  );

  static const hGap4 = SizedBox(
    width: 4,
  );
  static const hGap8 = SizedBox(
    width: 8,
  );
  static const hGap12 = SizedBox(
    width: 12,
  );
  static const hGap16 = SizedBox(
    width: 16,
  );

  static const hGap24 = SizedBox(
    width: 24,
  );
  static const hGap32 = SizedBox(
    width: 32,
  );
  static const hGap48 = SizedBox(
    width: 48,
  );

  static const edgeInsetsH4 = EdgeInsets.symmetric(horizontal: 4);
  static const edgeInsetsH8 = EdgeInsets.symmetric(horizontal: 8);
  static const edgeInsetsH12 = EdgeInsets.symmetric(horizontal: 12);
  static const edgeInsetsH16 = EdgeInsets.symmetric(horizontal: 16);
  static const edgeInsetsH20 = EdgeInsets.symmetric(horizontal: 20);
  static const edgeInsetsH24 = EdgeInsets.symmetric(horizontal: 24);

  static const edgeInsetsV4 = EdgeInsets.symmetric(vertical: 4);
  static const edgeInsetsV8 = EdgeInsets.symmetric(vertical: 8);
  static const edgeInsetsV12 = EdgeInsets.symmetric(vertical: 12);
  static const edgeInsetsV24 = EdgeInsets.symmetric(vertical: 24);

  static const edgeInsetsA4 = EdgeInsets.all(4);
  static const edgeInsetsA8 = EdgeInsets.all(8);
  static const edgeInsetsA12 = EdgeInsets.all(12);
  static const edgeInsetsA16 = EdgeInsets.all(16);
  static const edgeInsetsA20 = EdgeInsets.all(20);
  static const edgeInsetsA24 = EdgeInsets.all(24);

  static const edgeInsetsR4 = EdgeInsets.only(right: 4);
  static const edgeInsetsR8 = EdgeInsets.only(right: 8);
  static const edgeInsetsR12 = EdgeInsets.only(right: 12);
  static const edgeInsetsR16 = EdgeInsets.only(right: 16);
  static const edgeInsetsR20 = EdgeInsets.only(right: 20);
  static const edgeInsetsR24 = EdgeInsets.only(right: 24);

  static const edgeInsetsL4 = EdgeInsets.only(left: 4);
  static const edgeInsetsL8 = EdgeInsets.only(left: 8);
  static const edgeInsetsL12 = EdgeInsets.only(left: 12);
  static const edgeInsetsL16 = EdgeInsets.only(left: 16);
  static const edgeInsetsL20 = EdgeInsets.only(left: 20);
  static const edgeInsetsL24 = EdgeInsets.only(left: 24);

  static const edgeInsetsT4 = EdgeInsets.only(top: 4);
  static const edgeInsetsT8 = EdgeInsets.only(top: 8);
  static const edgeInsetsT12 = EdgeInsets.only(top: 12);
  static const edgeInsetsT24 = EdgeInsets.only(top: 24);

  static const edgeInsetsB4 = EdgeInsets.only(bottom: 4);
  static const edgeInsetsB8 = EdgeInsets.only(bottom: 8);
  static const edgeInsetsB12 = EdgeInsets.only(bottom: 12);
  static const edgeInsetsB24 = EdgeInsets.only(bottom: 24);

  static BorderRadius radius4 = BorderRadius.circular(4);
  static BorderRadius radius8 = BorderRadius.circular(8);
  static BorderRadius radius12 = BorderRadius.circular(12);
  static BorderRadius radius16 = BorderRadius.circular(16);
  static BorderRadius radius24 = BorderRadius.circular(24);
  static BorderRadius radius32 = BorderRadius.circular(32);
  static BorderRadius radius48 = BorderRadius.circular(48);

  /// 顶部状态栏的高度
  static double get statusBarHeight => MediaQuery.of(Get.context!).padding.top;

  /// 底部导航条的高度
  ///
  /// 退出全屏后部分设备不会再上报恢复后的系统栏高度，直接用
  /// [MediaQueryData.padding] 会让底部按钮压在导航条下，见 [SystemUiBottomInset]。
  ///
  /// **必须传调用方自己的 [context]**：这样该 widget 才会对
  /// `MediaQuery` 建立依赖，平台补报 insets 时能自动重建、自己恢复
  /// （早前用 `Get.context` 时依赖注册在根 element 上，页面不会重建，
  /// 底部避让会一直停在错误值上，只能靠触摸/侧滑等外部事件把页面叫醒）。
  static double bottomBarHeightOf(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return SystemUiBottomInset.resolve(
      mediaQuery.padding.bottom,
      systemBar: mediaQuery.viewPadding.bottom,
      viewSize: mediaQuery.size,
    );
  }

  static Divider get divider => Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: Colors.grey.withAlpha(25),
      );

  /// 未开播内容的压暗蒙版：R/G/B 各乘 0.55，等价于叠一层 45% 的黑色蒙版。
  ///
  /// 用来把「未开播」和「直播中」拉开区分度。**是保留色相地压暗，不是去饱和**——
  /// 头像整张转灰度会看着像遗像，用户明确否过（2026-09-13）。
  ///
  /// 写成矩阵而不是真盖一层半透明黑：乘法只作用在颜色通道上，第四行仍是
  /// `0,0,0,1,0`，alpha 原样透传，圆形头像的抗锯齿边缘不会渗出一圈黑边，
  /// 也就不需要额外套 `ClipOval` 去裁蒙版。
  ///
  /// 网格样式（`LiveRoomCard`）和紧凑样式（`FollowUserItem`）**共用这一个常量**，
  /// 别在各自文件里再写一份——两边走偏正是之前「两种样式不一致」的来源。
  static const ColorFilter offlineDim = ColorFilter.matrix(<double>[
    0.55, 0, 0, 0, 0, //
    0, 0.55, 0, 0, 0, //
    0, 0, 0.55, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
}
