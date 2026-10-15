import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:logger/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/app_scroll_behavior.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/listen_fourth_button.dart';
import 'package:simple_live_app/firebase_options.dart';
import 'package:simple_live_app/hive_registrar.g.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';
import 'package:simple_live_app/modules/other/debug_log_page.dart';
import 'package:simple_live_app/modules/settings/appstyle_settings/appstyle_setting_contorller.dart';
import 'package:simple_live_app/routes/app_analytics_observer.dart';
import 'package:simple_live_app/routes/app_pages.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/firebase_service.dart' as app;
import 'package:simple_live_app/services/follow_block_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/history_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/migration_service.dart';
import 'package:simple_live_app/services/platform_service.dart';
import 'package:simple_live_app/services/playback/live_playback_audio_handler.dart';
import 'package:simple_live_app/services/smart_group_service.dart';
import 'package:simple_live_app/services/stream_relay/stream_relay_service.dart';
import 'package:simple_live_app/services/sync_service.dart';
import 'package:simple_live_app/services/window_service.dart';
import 'package:simple_live_app/src/rust/frb_generated.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:window_manager/window_manager.dart';

void main(List<String> arguments) async {
  final action = arguments.isEmpty ? null : arguments.first.toLowerCase();
  var path = (await getApplicationSupportDirectory()).path;
  if (!Platform.isAndroid && !Platform.isIOS) {
    var pathPortable = p.join(p.dirname(Platform.resolvedExecutable), 'data_hive_ce');
    bool dirPortableExist = await Directory(pathPortable).exists();
    if (action == "-p" || action == "--portable" || dirPortableExist) {
      path = pathPortable;
    } else if (action == "-h" || action == "--help") {
      printHelp();
      return;
    } else if (action != null) {
      print("未知指令: $action");
      printHelp();
      return;
    }
  }
  WidgetsFlutterBinding.ensureInitialized();
  // init-queue:
  // window(first)->migration->media_kit->Hive->services->start
  // window(second)->open
  await RustLib.init();
  // await MigrationService.migrateData();
  MediaKit.ensureInitialized();
  await Hive.initFlutter(
    (!Platform.isAndroid && !Platform.isIOS) ? path : null,
  );
  //初始化服务
  await initServices();
  // 后台播放：AudioService.init 必须在 runApp 之前，且要等 Get.put 那批服务就位。
  // 函数内部自己判平台，桌面端是纯 no-op；失败也只降级成「没有通知栏控制」，不挡启动。
  await initLivePlaybackAudioHandler();
  await initWindow();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  //设置状态栏为透明
  SystemUiOverlayStyle systemUiOverlayStyle = const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
  );
  SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
  runApp(const MyApp());
}

void printHelp() {
  print("-p ：便携版启动");
  print("--portable：便携版启动");
  print("-h：帮助");
}

Future initWindow() async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return;
  }
  await windowManager.ensureInitialized();
  WindowService.instance.init();
}

Future initServices() async {
  Hive.registerAdapters();

  //包信息
  Utils.packageInfo = await PackageInfo.fromPlatform();
  //本地存储
  Log.d("Init LocalStorage Service");
  await Get.put(LocalStorageService()).init();
  await Get.put(DBService()).init();
  //初始化设置控制器
  await Get.put(AppSettingsController()).onInit();

  await Get.put(AppStyleSettingController()).init();

  Get.put(FollowService());
  // 智能分组：一键按平台归组（依赖 FollowService，紧随其后注册）
  Get.put(SmartGroupService());

  // platformService need migrate
  await MigrationService.migrateDataByVersion();

  Get.put(PlatformService());

  Get.put(SyncService());

  Get.put(HistoryService());

  Get.put(FollowBlockService());

  // 续流中转：斗鱼等平台直链带时效，由它接管「到期前重新取流」，避免断流。
  // 服务本身惰性启动（首次登记线路时才绑定本地端口）。
  Get.put(StreamRelayService());

  // 移动平台不使用 windowManager
  if (!Platform.isAndroid && !Platform.isIOS) {
    Get.put(WindowService());
  }

  // only android use firebase
  if (Platform.isAndroid) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    Get.put(app.FirebaseService());
  }

  initCoreLog();
}

void initCoreLog() {
  //日志信息
  CoreLog.enableLog = !kReleaseMode || AppSettingsController.instance.logEnable.value;
  CoreLog.requestLogType = RequestLogType.short;
  CoreLog.onPrintLog = (level, msg) {
    switch (level) {
      case Level.debug:
        Log.d(msg);
        break;
      case Level.error:
        Log.e(msg, StackTrace.current);
        break;
      case Level.info:
        Log.i(msg);
        break;
      case Level.warning:
        Log.w(msg);
        break;
      default:
        Log.logPrint(msg);
    }
  };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// 桌面端返回：优先关闭 SmartDialog 弹窗
  /// SmartDialog 的 useSystem 弹窗由 Navigator 路由承载，
  /// 若被 Get.back() 直接弹出，后续 dismiss 会再次 pop 导致 Navigator 状态异常
  ///
  /// 实现已搬到 `Utils.appBack`（直播间快捷键挂件也要用它，而它不能 import 本文件，
  /// 见那边的注释）。这里留一层委托：两处调用点（侧键手势、Esc 链）的写法不变。
  static void appBack() => Utils.appBack();

  @override
  Widget build(BuildContext context) {
    bool isDynamicColor = AppStyleSettingController.instance.isDynamic.value;
    Color styleColor =
        Color(AppStyleSettingController.instance.styleColor.value);
    return DynamicColorBuilder(
        builder: ((ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
      // 两个分支都赋非空值（动态取色拿不到或用户没开时回落到 styleColor
      // 生成的调色板），所以声明成**非空**局部变量：下面 appBarTheme 要取
      // `.surface`，声明成可空这里就编译不过。
      ColorScheme lightColorScheme;
      ColorScheme darkColorScheme;
      if (lightDynamic != null && darkDynamic != null && isDynamicColor) {
        lightColorScheme = lightDynamic;
        darkColorScheme = darkDynamic;
      } else {
        lightColorScheme = ColorScheme.fromSeed(
          seedColor: styleColor,
          brightness: Brightness.light,
        );
        darkColorScheme = ColorScheme.fromSeed(seedColor: styleColor, brightness: Brightness.dark);
      }
      return Obx(
        () => GetMaterialApp(
          title: "Slive",
          theme: AppStyle.light(
            fontFamily: AppStyleSettingController.instance.curFontName.value,
          ).copyWith(
            colorScheme: lightColorScheme,
            // AppBar 的背景钉在 AppStyle 的固定调色板上，这里换成实际生效的
            // colorScheme，否则用户改主题色 / 开动态取色后 AppBar 会和页面
            // 底色不一致（详见 app_style.dart 里 appBarTheme 的注释）。
            appBarTheme: AppStyle.light().appBarTheme.copyWith(
                  backgroundColor: lightColorScheme.surface,
                ),
          ),
          darkTheme: AppStyle.darkTheme(
            fontFamily: AppStyleSettingController.instance.curFontName.value,
          ).copyWith(
            colorScheme: darkColorScheme,
            appBarTheme: AppStyle.darkTheme().appBarTheme.copyWith(
                  backgroundColor: darkColorScheme.surface,
                ),
          ),
          themeMode: ThemeMode
              .values[Get.find<AppSettingsController>().themeMode.value],
          // 桌面端放开鼠标拖拽：上下拖列表、左右拖切换平台标签，
          // 与移动端保持一致（默认行为只认触摸类指针，鼠标拖不动）。
          scrollBehavior: const AppScrollBehavior(),
          initialRoute: RoutePath.kIndex,
          getPages: AppPages.routes,
          //国际化
          locale: const Locale("zh", "CN"),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale("zh", "CN")],
          logWriterCallback: (text, {bool? isError}) {
            Log.addDebugLog(text, (isError ?? false) ? Colors.red : Colors.grey);
            Log.writeLog(text, (isError ?? false) ? Level.error : Level.info);
          },
          //debugShowCheckedModeBanner: false,
          navigatorObservers: [FlutterSmartDialog.observer, if (Platform.isAndroid) AppAnalyticsObserver.observer],
          builder: FlutterSmartDialog.init(
            loadingBuilder: ((msg) => const AppLoaddingWidget()),
            //字体大小不跟随系统变化
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.0)),
              child: Stack(
                children: [
                  //侧键返回
                  RawGestureDetector(
                    excludeFromSemantics: true,
                    gestures: <Type, GestureRecognizerFactory>{
                      FourthButtonTapGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              FourthButtonTapGestureRecognizer>(
                        () => FourthButtonTapGestureRecognizer(),
                        (FourthButtonTapGestureRecognizer instance) {
                          instance.onTapDown =
                              (TapDownDetails details) async {
                            //优先关闭 SmartDialog 弹窗
                            if (SmartDialog.checkExist()) {
                              MyApp.appBack();
                              return;
                            }
                            //如果处于全屏状态，退出全屏
                            if (!Platform.isAndroid && !Platform.isIOS) {
                              if (await windowManager.isFullScreen()) {
                                await windowManager.setFullScreen(false);
                                // 必须像下面 Esc 那条链一样补发事件，把退出交回
                                // exitFull：只裸调 setFullScreen(false) 就 return，
                                // 控制器的 fullScreenState / smallWindowState 会停在
                                // true（「幽灵全屏」：OS 已回窗口，UI 还画全屏那套）。
                                // 更要命的是还原点——_captureNormalGeometry 的守卫
                                // 见标志为真就不重采，于是这次改的窗口尺寸记不进去，
                                // 下一次退全屏仍落回旧矩形。
                                // 复用 kEscapePressed 而不另立名字：它的订阅者
                                // （player_controller 里 allowsWindowOps 那一个）就是
                                // exitFull，语义正是「退出全屏」，且天然避开
                                // main → live_room_controller 这条循环 import。
                                EventBus.instance.emit(
                                    EventBus.kEscapePressed, 0);
                                return;
                              }
                            }
                            // 同 appBack：走 maybePop，否则会绕过直播间页的 PopScope
                            // （多开时那一下本该只收起其余几路，而不是把整页弹掉）
                            Get.key.currentState?.maybePop();
                          };
                        },
                      ),
                    },
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (KeyEvent event) async {
                        // 「退出/关闭播放器」这一行的**全局兜底**：键位可自定义，
                        // 默认仍是 Escape。行为链本身与改前逐字一致。
                        //
                        // 直播间视频区拿到焦点时，这条链不会走到这里——那里的
                        // `PlayerShortcuts` 更深一层，会先消费掉同一个键并加上
                        // 「离开直播间」这第三级。焦点在别处（设置页、聊天输入框、
                        // 首页）时，本处仍是唯一入口，所以「Esc 关弹窗」在全 app
                        // 范围内照旧可用，且不受「播放器快捷键」总开关影响：
                        // 那个开关管的是播放器动作，不是应用级的弹窗/全屏收口。
                        if (event is! KeyDownEvent) {
                          return;
                        }
                        final exitBinding = AppSettingsController.instance
                            .bindingFor(PlayerShortcut.exitPlayer);
                        if (exitBinding == null) {
                          return;
                        }
                        final hk = HardwareKeyboard.instance;
                        if (!shortcutBindingMatches(
                          exitBinding,
                          event.logicalKey,
                          shift: hk.isShiftPressed,
                          ctrl: hk.isControlPressed,
                          alt: hk.isAltPressed,
                          meta: hk.isMetaPressed,
                        )) {
                          return;
                        }
                        //优先关闭 SmartDialog 弹窗
                        if (SmartDialog.checkExist()) {
                          MyApp.appBack();
                          return;
                        }
                        // ESC退出全屏
                        // 如果处于全屏状态，退出全屏
                        if (!Platform.isAndroid && !Platform.isIOS) {
                          if (await windowManager.isFullScreen()) {
                            await windowManager.setFullScreen(false);
                            EventBus.instance
                                .emit(EventBus.kEscapePressed, 0);
                            return;
                          }
                        }
                      },
                      child: child!,
                    ),
                  ),

                  //查看DEBUG日志按钮
                  //只在Debug、Profile模式显示
                  Visibility(
                    visible: !kReleaseMode,
                    child: Positioned(
                      right: 12,
                      bottom: 100 + context.mediaQueryViewPadding.bottom,
                      child: Opacity(
                        opacity: 0.4,
                        child: ElevatedButton(
                          child: const Text("DEBUG LOG"),
                          onPressed: () {
                            Get.bottomSheet(
                              const DebugLogPage(),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }));
  }
}
