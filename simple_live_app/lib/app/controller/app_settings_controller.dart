import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_snapshot.dart';
import 'package:simple_live_app/modules/live_room/multi_play/multi_play_layout.dart';
import 'package:simple_live_app/modules/live_room/player/shortcut_binding.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

class AppSettingsController extends GetxController {
  static AppSettingsController get instance => Get.find<AppSettingsController>();

  /// 桌面端
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// 缩放模式
  var scaleMode = 0.obs;

  var aspectByUser = (16 / 9).obs;

  var aspectWidth = 16.obs;

  var aspectHeight = 9.obs;

  /// 显示模式
  /// * [0] 跟随系统
  /// * [1] 浅色模式
  /// * [2] 深色模式
  var themeMode = 0.obs;

  /// 主题索引归一化（越界按「跟随系统」处理）
  static int normalizeThemeModeIndex(int index) =>
      (index >= 0 && index < ThemeMode.values.length) ? index : 0;

  /// 主题索引对应的 [ThemeMode]
  static ThemeMode resolveThemeMode(int index) =>
      ThemeMode.values[normalizeThemeModeIndex(index)];

  /// 当前主题索引（已归一化，可安全用于索引 [ThemeMode.values]）
  int get themeModeIndex => normalizeThemeModeIndex(themeMode.value);

  /// 应用当前是否应使用深色主题。
  /// [platformDark] 为系统深浅色，仅在「跟随系统」时参与判断。
  /// 主题判定统一放在这里，避免各处重复解析（注意 material_ui 与 flutter
  /// 各自定义了同名的 ThemeMode 类型，跨库比较会失效）。
  bool shouldUseDarkTheme({required bool platformDark}) =>
      switch (resolveThemeMode(themeMode.value)) {
        ThemeMode.dark => true,
        ThemeMode.light => false,
        ThemeMode.system => platformDark,
      };

  /// 主题模式统一由本控制器持有，其它地方（设置页、Windows 标题栏等）
  /// 必须通过此方法修改，避免出现多份互不同步的主题状态
  void setThemeMode(int e) {
    final index = normalizeThemeModeIndex(e);
    themeMode.value = index;
    LocalStorageService.instance
        .setValue(LocalStorageService.kThemeMode, index);
  }

  var firstRun = false;

  var dbVer = 0;

  var dbPath = "";

  @override
  Future<void> onInit() async {
    // 存量数据可能越界，统一走归一化，避免 main.dart 的
    // ThemeMode.values[...] 在启动时抛 RangeError
    themeMode.value = normalizeThemeModeIndex(
      LocalStorageService.instance.getValue(LocalStorageService.kThemeMode, 0),
    );
    // 旧版本只有「悬浮玻璃导航栏」开关，再往后是 0/1/2 的样式枚举。
    // 整合后悬浮玻璃不再是独立样式，旧值 2（悬浮玻璃）与早期开关一律迁移为
    // 样式 1（悬浮 dock）。
    final legacyGlassNavBar = LocalStorageService.instance
        .getValue(LocalStorageService.kFloatingGlassNavBar, false);
    final storedNavBarStyle = LocalStorageService.instance
        .getNullValue<int>(LocalStorageService.kNavBarStyle, null);
    final resolvedNavBarStyle =
        (storedNavBarStyle == null && legacyGlassNavBar) || storedNavBarStyle == 2
        ? 1
        : (storedNavBarStyle ?? 0);
    navBarStyle.value = resolvedNavBarStyle >= 1 ? 1 : 0;
    hideTopBar.value = LocalStorageService.instance
        .getValue(LocalStorageService.kHideTopBar, hideTopBar.value);
    hideBottomBar.value = LocalStorageService.instance
        .getValue(LocalStorageService.kHideBottomBar, hideBottomBar.value);
    barHideType.value = LocalStorageService.instance
        .getValue(LocalStorageService.kBarHideType, barHideType.value);
    firstRun = LocalStorageService.instance
        .getValue(LocalStorageService.kFirstRun, true);
    danmuSize.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuSize, 16.0);
    danmuOpacity.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuOpacity, 1.0);
    danmuArea.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuArea, 0.8);
    danmuSpeed.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuSpeed, 10.0);
    danmuEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuEnable, true);
    danmakuMaskEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmakuMaskEnable, false);
    danmuStrokeWidth.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuStrokeWidth, 2.0);
    danmuTopMargin.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuTopMargin, 0.0);
    danmuBottomMargin.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuBottomMargin, 0.0);
    danmuFontWeight.value = LocalStorageService.instance.getValue(
        LocalStorageService.kDanmuFontWeight,
        // ignore: deprecated_member_use
        FontWeight.normal.index);
    // limit of canvas_danmaku interface, there is bug if change index to value
    // and now, value was set 0..8, the value needs ..=FontWeight[index] after
    // migration, so marked it, next migration depends on canvas_danmaku upgrade
    danmakuFontClamped.value = LocalStorageService.instance.getValue(LocalStorageService.kDanmakuFontClamped, false);
    danmakuFontClampUpSens.value = LocalStorageService.instance.getValue(LocalStorageService.kDanmakuFontClampUpSens, 9.0);
    danmakuFontClampDownSens.value = LocalStorageService.instance.getValue(LocalStorageService.kDanmakuFontClampDownSens, 5.0);

    hardwareDecode.value = LocalStorageService.instance.getValue(LocalStorageService.kHardwareDecode, true);
    chatTextSize.value = LocalStorageService.instance.getValue(LocalStorageService.kChatTextSize, 14.0);

    chatTextGap.value = LocalStorageService.instance.getValue(LocalStorageService.kChatTextGap, 4.0);

    chatBubbleStyle.value = LocalStorageService.instance.getValue(
      LocalStorageService.kChatBubbleStyle,
      false,
    );

    qualityLevel.value = LocalStorageService.instance.getValue(LocalStorageService.kQualityLevel, 2);
    qualityLevelCellular.value = LocalStorageService.instance.getValue(LocalStorageService.kQualityLevelCellular, 1);

    autoExitEnable.value = LocalStorageService.instance.getValue(LocalStorageService.kAutoExitEnable, false);

    autoExitDuration.value = LocalStorageService.instance.getValue(LocalStorageService.kAutoExitDuration, 60);

    roomAutoExitDuration.value = LocalStorageService.instance.getValue(LocalStorageService.kRoomAutoExitDuration, 60);

    playerCompatMode.value = LocalStorageService.instance.getValue(LocalStorageService.kPlayerCompatMode, false);

    playerAutoPause.value = LocalStorageService.instance.getValue(LocalStorageService.kPlayerAutoPause, false);

    backgroundPlay.value = LocalStorageService.instance.getValue(LocalStorageService.kBackgroundPlay, false);
    // 桌面端恒按「关」处理：这一行在桌面的设置页上根本不显示，而设置是会经 WebDAV
    // 从手机同步过来的——真值落到桌面就会悄悄关掉「进入后台自动暂停」，且界面上没有
    // 任何地方能改回来。只压内存值、不动磁盘：同一份存储回到手机上时那个选择还算数。
    if (isDesktop && backgroundPlay.value) {
      backgroundPlay.value = false;
    }
    // 正常路径下两者不会同时为真（两个 setter 互斥）。存储被外部改过就以后台播放为准：
    // 留着自动暂停的话切后台那一刻就被暂停，「后台播放」等于没开。
    if (backgroundPlay.value && playerAutoPause.value) {
      playerAutoPause.value = false;
      LocalStorageService.instance.setValue(LocalStorageService.kPlayerAutoPause, false);
    }

    playerForceHttps.value = LocalStorageService.instance.getValue(LocalStorageService.kPlayerForceHttps, false);

    douyinHlsFirst.value = LocalStorageService.instance.getValue(LocalStorageService.kDouyinHlsFirst, false);

    autoFullScreen.value = LocalStorageService.instance.getValue(LocalStorageService.kAutoFullScreen, false);

    verticalDragLock.value = LocalStorageService.instance.getValue(LocalStorageService.kVerticalDragLock, false);

    keyboardControl.value = LocalStorageService.instance.getValue(LocalStorageService.kKeyboardControl, true);

    loadShortcuts();

    // ignore: invalid_use_of_protected_member
    shieldList.value = LocalStorageService.instance.shieldBox.values.toSet();

    scaleMode.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerScaleMode,
      0,
    );

    aspectByUser.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerAspectByUser,
      16 / 9,
    );

    aspectWidth.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerAspectWidth,
      16,
    );

    aspectHeight.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerAspectHeight,
      9,
    );

    playerVolume.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerVolume,
      100.0,
    );
    playerMaxVolume.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerMaxVolume,
      100,
    );
    pipHideDanmu.value = LocalStorageService.instance.getValue(LocalStorageService.kPIPHideDanmu, true);
    pipLockAspect.value = LocalStorageService.instance.getValue(LocalStorageService.kPipLockAspect, true);

    windowMaxAuto.value = LocalStorageService.instance.getValue(LocalStorageService.kWindowMaxAuto, false);
    windowMaxState.value = LocalStorageService.instance.getValue(LocalStorageService.kWindowMaxState, false);

    windowPipX.value = LocalStorageService.instance.getValue(LocalStorageService.kWindowPipX, 0.0);
    windowPipY.value = LocalStorageService.instance.getValue(LocalStorageService.kWindowPipY, 0.0);
    windowPipWidth.value = LocalStorageService.instance.getValue(LocalStorageService.kWindowPipWidth, 400.0);
    windowPipHeight.value = LocalStorageService.instance.getValue(LocalStorageService.kWindowPipHeight, 225.0);

    bilibiliLoginTip.value = LocalStorageService.instance.getValue(LocalStorageService.kBilibiliLoginTip, true);

    playerBufferSize.value = LocalStorageService.instance.getValue(LocalStorageService.kPlayerBufferSize, 32);

    logEnable.value = LocalStorageService.instance.getValue(LocalStorageService.kLogEnable, false);
    if (logEnable.value) {
      Log.initWriter();
    }

    firebaseEnable.value = LocalStorageService.instance.getValue(LocalStorageService.kFirebaseEnable, true);

    customPlayerOutput.value = LocalStorageService.instance.getValue(LocalStorageService.kCustomPlayerOutput, false);

    videoOutputDriver.value = LocalStorageService.instance.getValue(
      LocalStorageService.kVideoOutputDriver,
      Platform.isAndroid ? "mediacodec_embed" : "libmpv",
    );

    audioOutputDriver.value = LocalStorageService.instance.getValue(
      LocalStorageService.kAudioOutputDriver,
      Platform.isAndroid
          ? "audiotrack"
          : Platform.isLinux
              ? "pulse"
              : Platform.isWindows
                  ? "wasapi"
                  : Platform.isIOS
                      ? "audiounit"
                      : Platform.isMacOS
                          ? "coreaudio"
                          : "sdl",
    );

    videoHardwareDecoder.value = LocalStorageService.instance.getValue(
      LocalStorageService.kVideoHardwareDecoder,
      Platform.isAndroid ? "mediacodec" : "auto",
    );

    videoDoubleBuffering.value = LocalStorageService.instance.getValue(
      LocalStorageService.kVideoDoubleBuffering,
      false,
    );

    multiPlayEnable.value = LocalStorageService.instance.getValue(
      LocalStorageService.kMultiPlayEnable,
      false,
    );

    multiPlayDuckVolume.value = LocalStorageService.instance.getValue(
      LocalStorageService.kMultiPlayDuckVolume,
      0.3,
    );

    multiPlayDuckEnabled.value = LocalStorageService.instance.getValue(
      LocalStorageService.kMultiPlayDuckEnable,
      false,
    );

    multiPlayTileBufferSize.value = LocalStorageService.instance.getValue(
      LocalStorageService.kMultiPlayTileBufferSize,
      16,
    );

    multiPlayTileDanmaku.value = LocalStorageService.instance.getValue(
      LocalStorageService.kMultiPlayTileDanmaku,
      true,
    );

    // 「默认路数」不给存储层的默认值，而是先读成 null 交给
    // `resolveDefaultMultiPlayTiles` 按平台预填：桌面 4、移动 2。
    // 直接在这里写死一个数会让移动端也拿到 4（然后被布局引擎折格），
    // 写死成 2 又会让桌面端永远只能开两路。
    multiPlayDefaultTiles.value = resolveDefaultMultiPlayTiles(
      isDesktop: isDesktop,
      stored: LocalStorageService.instance.getValue<int?>(
        LocalStorageService.kMultiPlayDefaultTiles,
        null,
      ),
    );

    enableRtxVsr.value = LocalStorageService.instance.getValue(
      LocalStorageService.kEnableRtxVsr,
      false,
    );

    volumeNormalize.value = LocalStorageService.instance.getValue(
      LocalStorageService.kVolumeNormalize,
      true,
    );

    volumeNormalizeTargetLufs.value = LocalStorageService.instance.getValue(
      LocalStorageService.kVolumeNormalizeTargetLufs,
      -16,
    );

    osdBackend.value = LocalStorageService.instance.getValue(
      LocalStorageService.kOSDBackend,
      "app",
    );

    autoUpdateFollowEnable.value =
        LocalStorageService.instance.getValue(LocalStorageService.kAutoUpdateFollowEnable, true);

    autoUpdateFollowDuration.value =
        LocalStorageService.instance.getValue(LocalStorageService.kUpdateFollowDuration, 10);

    updateFollowThreadCount.value =
        LocalStorageService.instance.getValue(LocalStorageService.kUpdateFollowThreadCount, 4);

    followSnapshotEnable.value =
        LocalStorageService.instance.getValue(LocalStorageService.kFollowSnapshotEnable, false);

    dormancyThreshold.value = LocalStorageService.instance.getValue(LocalStorageService.kDormancyThreshold, 0);

    // danmaku-去重参数
    danmuFrequencyControl.value =
        LocalStorageService.instance.getValue(LocalStorageService.kDanmuFrequencyControl, false);

    danmuMaxFrequency.value = LocalStorageService.instance.getValue(LocalStorageService.kDanmuMaxFrequency, 3);

    danmuTextNormalization.value =
        LocalStorageService.instance.getValue(LocalStorageService.kDanmuTextNormalization, true);

    danmuWindowMs.value = LocalStorageService.instance.getValue(LocalStorageService.kDanmuWindowMs, 15);
    dbVer = LocalStorageService.instance.getValue(LocalStorageService.kHiveDbVer, 10708);

    followSortMethod.value = SortMethodStore.fromStore(LocalStorageService.instance
        .getValue(LocalStorageService.kFollowSortMethod, SortMethod.watchDuration.storeValue));

    followCollapsedGroups.assignAll(LocalStorageService.instance
        .getValue(LocalStorageService.kFollowCollapsedGroups, "")
        .split(",")
        .where((s) => s.isNotEmpty));

    followStyleNotGrid.value = LocalStorageService.instance.getValue(LocalStorageService.kFollowStyleNotGrid, true);

    hideOfflineFollow.value = LocalStorageService.instance.getValue(LocalStorageService.kHideOfflineFollow, false);

    // 默认**显示**快速取关按钮（`false`）。
    // 上游默认是 `true`（隐藏），但关注页上下两段同屏时，隐藏状态下取关只能靠长按
    // 弹底部菜单，取关路径太长（用户实测反馈）。保留开关本身，想要清爽列表的仍可自行打开。
    hideRemoveFollowButton.value = LocalStorageService.instance.getValue(LocalStorageService.kHideRemoveFollow, false);

    followSnapshot = LocalStorageService.instance.getNullValue(LocalStorageService.kFollowSnapshot, null);

    initSiteSort();
    initHomeSort();
    await initDataPath();

    super.onInit();
  }

  Future<void> initDataPath() async {
    dbPath = (await getApplicationSupportDirectory()).path;
    if(!Platform.isAndroid && !Platform.isIOS){
      // linux 应该有问题，但我不熟悉，先这么写
      var pathPortable = p.join(p.dirname(Platform.resolvedExecutable), 'data_hive_ce');
      bool dirPortableExist = await Directory(pathPortable).exists();
      if(dirPortableExist){
        dbPath = pathPortable;
      }
    }
  }

  void initSiteSort() {
    var sort = LocalStorageService.instance
        .getValue(
          LocalStorageService.kSiteSort,
          Sites.allSites.keys.join(","),
        )
        .split(",");
    //如果数量与allSites的数量不一致，将缺失的添加上
    if (sort.length != Sites.allSites.length) {
      var keys = Sites.allSites.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        if (!sort.contains(keys[i])) {
          sort.add(keys[i]);
        }
      }
    }

    siteSort.value = sort;
  }

  void initHomeSort() {
    var sort = LocalStorageService.instance
        .getValue(
          LocalStorageService.kHomeSort,
          Constant.allHomePages.keys.join(","),
        )
        .split(",");
    //如果数量与allSites的数量不一致，将缺失的添加上
    if (sort.length != Constant.allHomePages.length) {
      var keys = Constant.allHomePages.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        if (!sort.contains(keys[i])) {
          sort.add(keys[i]);
        }
      }
    }

    homeSort.value = sort;
  }

  void setNoFirstRun() {
    LocalStorageService.instance.setValue(LocalStorageService.kFirstRun, false);
  }

  /// 底部导航栏样式（见 [LocalStorageService.kNavBarStyle]）
  /// * [0] 标准
  /// * [1] 悬浮 dock
  var navBarStyle = 0.obs;

  void setNavBarStyle(int e) {
    navBarStyle.value = e >= 1 ? 1 : 0;
    LocalStorageService.instance
        .setValue(LocalStorageService.kNavBarStyle, navBarStyle.value);
  }

  /// 首页顶栏收起（移动端默认开启）
  var hideTopBar = (!isDesktop).obs;

  void setHideTopBar(bool e) {
    hideTopBar.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kHideTopBar, e);
  }

  /// 首页底栏收起（移动端默认开启）
  var hideBottomBar = (!isDesktop).obs;

  void setHideBottomBar(bool e) {
    hideBottomBar.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kHideBottomBar, e);
  }

  /// 顶/底栏收起类型
  /// * [0] 即时
  /// * [1] 同步
  var barHideType = 1.obs;

  void setBarHideType(int e) {
    barHideType.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kBarHideType, e);
  }

  var hardwareDecode = true.obs;

  void setHardwareDecode(bool e) {
    hardwareDecode.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kHardwareDecode, e);
  }

  var chatTextSize = 14.0.obs;

  void setChatTextSize(double e) {
    chatTextSize.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kChatTextSize, e);
  }

  var chatTextGap = 4.0.obs;

  void setChatTextGap(double e) {
    chatTextGap.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kChatTextGap, e);
  }

  var chatBubbleStyle = false.obs;

  void setChatBubbleStyle(bool e) {
    chatBubbleStyle.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kChatBubbleStyle, e);
  }

  var danmuSize = 16.0.obs;

  void setDanmuSize(double e) {
    danmuSize.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuSize, e);
  }

  var danmuSpeed = 10.0.obs;

  void setDanmuSpeed(double e) {
    danmuSpeed.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuSpeed, e);
  }

  var danmuArea = 0.8.obs;

  void setDanmuArea(double e) {
    danmuArea.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuArea, e);
  }

  var danmuOpacity = 1.0.obs;

  void setDanmuOpacity(double e) {
    danmuOpacity.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuOpacity, e);
  }

  var danmuEnable = true.obs;

  void setDanmuEnable(bool e) {
    danmuEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuEnable, e);
  }

  var danmakuMaskEnable = false.obs;

  void setDanmakuMaskEnable(bool e) {
    danmakuMaskEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmakuMaskEnable, e);
  }

  var danmuStrokeWidth = 2.0.obs;

  void setDanmuStrokeWidth(double e) {
    danmuStrokeWidth.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuStrokeWidth, e);
  }

  // ignore: deprecated_member_use
  var danmuFontWeight = FontWeight.normal.index.obs;

  void setDanmuFontWeight(int e) {
    danmuFontWeight.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuFontWeight, e);
  }

  var danmakuFontClamped = false.obs;
  void setDanmakuFontClamped(bool e) {
    danmakuFontClamped.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmakuFontClamped, e);
  }
  var danmakuFontResize = 16.0;

  var danmakuFontClampUpSens = 9.0.obs;
  void setDanmakuFontClampUpSens(double e) {
    danmakuFontClampUpSens.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmakuFontClampUpSens, e);
  }

  var danmakuFontClampDownSens = 5.0.obs;
  void setDanmakuFontClampDownSens(double e) {
    danmakuFontClampDownSens.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmakuFontClampDownSens, e);
  }

  var qualityLevel = 1.obs;

  void setQualityLevel(int level) {
    qualityLevel.value = level;
    LocalStorageService.instance.setValue(LocalStorageService.kQualityLevel, level);
  }

  var qualityLevelCellular = 1.obs;

  void setQualityLevelCellular(int level) {
    qualityLevelCellular.value = level;
    LocalStorageService.instance.setValue(LocalStorageService.kQualityLevelCellular, level);
  }

  var autoExitEnable = false.obs;

  void setAutoExitEnable(bool e) {
    autoExitEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kAutoExitEnable, e);
  }

  var autoExitDuration = 60.obs;

  void setAutoExitDuration(int e) {
    autoExitDuration.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kAutoExitDuration, e);
  }

  var roomAutoExitDuration = 60.obs;

  void setRoomAutoExitDuration(int e) {
    roomAutoExitDuration.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kRoomAutoExitDuration, e);
  }

  var playerCompatMode = false.obs;

  void setPlayerCompatMode(bool e) {
    playerCompatMode.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kPlayerCompatMode, e);
  }

  var playerBufferSize = 32.obs;

  void setPlayerBufferSize(int e) {
    playerBufferSize.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kPlayerBufferSize, e);
  }

  var playerAutoPause = false.obs;

  void setPlayerAutoPause(bool e) {
    playerAutoPause.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kPlayerAutoPause, e);
    // 互斥：自动暂停一开，后台播放就名存实亡（切后台那一刻播放已被暂停），必须顶掉它。
    if (e && backgroundPlay.value) {
      _writeBackgroundPlay(false);
    }
    EventBus.instance.emit(EventBus.kBackgroundPlayChanged, backgroundPlay.value);
  }

  /// 后台播放：切后台/锁屏继续出声，并在通知栏与锁屏提供播放控制。
  ///
  /// 只在 Android/iOS 有意义——桌面没有前台服务这一层，设置页也不显示这一行。
  /// 与 [playerAutoPause] 互斥，两个 setter 各自负责把对方关掉（UI 只负责把被顶掉
  /// 的那一项锁上并给出原因）。
  ///
  /// 默认关：打开它会在 Android 上要求通知权限、并留下一条常驻媒体通知，
  /// 不该由一次升级替用户决定。
  var backgroundPlay = false.obs;

  void setBackgroundPlay(bool e) {
    _writeBackgroundPlay(e);
    if (e && playerAutoPause.value) {
      playerAutoPause.value = false;
      LocalStorageService.instance.setValue(LocalStorageService.kPlayerAutoPause, false);
    }
    EventBus.instance.emit(EventBus.kBackgroundPlayChanged, e);
  }

  /// [backgroundPlay] 唯一的落盘写入点，保证「内存值 == 磁盘值」这条不变式不被绕开。
  void _writeBackgroundPlay(bool e) {
    backgroundPlay.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kBackgroundPlay, e);
  }

  var autoFullScreen = false.obs;

  void setAutoFullScreen(bool e) {
    autoFullScreen.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kAutoFullScreen, e);
  }

  // todo: 构造一个settings struct,用于批量生成ui和配置参数
  // 滑动调节亮度/音量上下滑动手势控制
  var verticalDragLock = false.obs;

  void setVerticalDragLock(bool e) {
    verticalDragLock.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kVerticalDragLock, e);
  }

  /// 直播间键盘快捷键。关掉后视频区不再消费任何按键（Tab 导航等默认行为不受影响）。
  var keyboardControl = true.obs;

  void setKeyboardControl(bool e) {
    keyboardControl.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kKeyboardControl, e);
  }

  /// 播放器快捷键的**用户覆盖表**（不是生效表——生效表见 [effectiveShortcuts]）。
  ///
  /// 只存用户动过的项，所以「恢复默认」是把键删掉而不是写回默认值。
  /// 每次变更都换成一个**新 map 实例**再写回：`Rx` 的 setter 会在 `_value == val`
  /// 时直接不通知，而 Map 的 `==` 是同一性比较——原地改内容就永远刷不到订阅者，
  /// 设置页与播放器都会停在旧的那份上。
  ///
  /// 用 `Rx<Map<...>>` 而不是 `<...>{}.obs`：后者返回 `RxMap`，它不是 `Rx` 的子类型
  /// （是 `MapMixin + RxObjectMixin`），既接不住整体替换的写法，值类型也没法是可空的。
  final Rx<Map<PlayerShortcut, ShortcutBinding?>> shortcutOverrides =
      Rx<Map<PlayerShortcut, ShortcutBinding?>>({});

  /// 当前生效的完整键位表（每个动作一项；值为 null 表示该动作被「不设置」禁用）。
  ///
  /// 读它要在 `Obx` 里（会订阅 [shortcutOverrides]）。播放器挂件是在按键发生时
  /// 现读，不建订阅——它不需要「键位变了就重建」，只需要「按下的那一刻按最新配置解释」。
  Map<PlayerShortcut, ShortcutBinding?> get effectiveShortcuts =>
      resolveEffectiveShortcuts(shortcutOverrides.value);

  /// 某个动作此刻的绑定（含「不设置」＝null）。
  ShortcutBinding? bindingFor(PlayerShortcut action) =>
      effectiveShortcuts[action];

  void loadShortcuts() {
    shortcutOverrides.value = decodeShortcuts(
      LocalStorageService.instance.getValue(
        LocalStorageService.kPlayerShortcuts,
        "",
      ),
    );
  }

  void _saveShortcutOverrides() {
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerShortcuts,
      encodeShortcuts(shortcutOverrides.value),
    );
  }

  /// 给某个动作设一个绑定（含传 null 表示「不设置」）。
  void setShortcut(PlayerShortcut action, ShortcutBinding? binding) {
    final next = Map<PlayerShortcut, ShortcutBinding?>.of(
      shortcutOverrides.value,
    );
    next[action] = binding;
    shortcutOverrides.value = next;
    _saveShortcutOverrides();
  }

  /// 单个动作恢复默认：删掉覆盖项，而不是写回一份默认值快照。
  void resetShortcut(PlayerShortcut action) {
    if (!shortcutOverrides.value.containsKey(action)) {
      return;
    }
    final next = Map<PlayerShortcut, ShortcutBinding?>.of(
      shortcutOverrides.value,
    )..remove(action);
    shortcutOverrides.value = next;
    _saveShortcutOverrides();
  }

  /// 全部动作恢复默认（设置页右上角那颗 ↺）。
  void resetAllShortcuts() {
    if (shortcutOverrides.value.isEmpty) {
      return;
    }
    shortcutOverrides.value = <PlayerShortcut, ShortcutBinding?>{};
    _saveShortcutOverrides();
  }

  RxSet<String> shieldList = <String>{}.obs;

  void addShieldList(String e) {
    shieldList.add(e);
    LocalStorageService.instance.shieldBox.put(e, e);
  }

  void removeShieldList(String e) {
    shieldList.remove(e);
    LocalStorageService.instance.shieldBox.delete(e);
  }

  Future clearShieldList() async {
    shieldList.clear();
    await LocalStorageService.instance.shieldBox.clear();
  }

  void setScaleMode(int value) {
    scaleMode.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerScaleMode,
      value,
    );
  }

  void setAspectByUser(double value) {
    aspectByUser.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerAspectByUser,
      value,
    );
  }

  void setAspectWidth(int value) {
    aspectWidth.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerAspectWidth,
      value,
    );
  }

  void setAspectHeight(int value) {
    aspectHeight.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerAspectHeight,
      value,
    );
  }

  RxList<String> siteSort = RxList<String>();

  void setSiteSort(List<String> e) {
    siteSort.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kSiteSort,
      siteSort.join(","),
    );
  }

  RxList<String> homeSort = RxList<String>();

  void setHomeSort(List<String> e) {
    homeSort.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kHomeSort,
      homeSort.join(","),
    );
  }

  Rx<double> playerVolume = 100.0.obs;

  void setPlayerVolume(double value) {
    playerVolume.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerVolume,
      value,
    );
  }

  /// 播放器最大音量（mpv volume-max）。100 为不放大，130 是 mpv 官方默认上限。
  Rx<int> playerMaxVolume = 100.obs;

  void setPlayerMaxVolume(int e) {
    playerMaxVolume.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerMaxVolume,
      e,
    );
    // 上限调低时把当前音量一并夹到上限内，避免滑块位置越界
    // （音量本身由 mpv 按 volume-max 截断，不必另行下发）
    if (playerVolume.value > e) {
      setPlayerVolume(e.toDouble());
    }
    // 通知当前播放器重设 volume-max，不必重进直播间
    EventBus.instance.emit(EventBus.kPlayerMaxVolumeChanged, e);
  }

  /// 多开播放：记住上次的布局模式（单画面 / 多画面）。
  ///
  /// 注意它只表示「上次是不是多画面」；真正的多开是否成立还要看已经加了几路
  /// （见 `MultiPlaySession.isActive`）。
  var multiPlayEnable = false.obs;

  void setMultiPlayEnable(bool e) {
    multiPlayEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kMultiPlayEnable, e);
  }

  /// 多开播放：非聚焦格的音量比例，乘在总音量上。
  ///
  /// 默认 0.3（≈ −10.5 dB）：开压低时是「聚焦格正常、其余压低」而不是静音，所以刻意不取 0。
  /// 允许 0 但那是用户自己的选择，滑块到 0 附近是渐弱而非突变。
  var multiPlayDuckVolume = 0.3.obs;

  void setMultiPlayDuckVolume(double e) {
    multiPlayDuckVolume.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kMultiPlayDuckVolume,
      e,
    );
  }

  /// 多开播放：非聚焦格是否自动压低。
  ///
  /// 默认关：主模型是「每一路自己说了算」，压低只是给习惯「聚焦即安静」的人的可选行为。
  /// 关掉时 [multiPlayDuckVolume] 原样留着，重新打开不用再调一遍。
  var multiPlayDuckEnabled = false.obs;

  void setMultiPlayDuckEnabled(bool e) {
    multiPlayDuckEnabled.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kMultiPlayDuckEnable,
      e,
    );
  }

  /// 多开播放：副格的 mpv 缓存上限（MiB）。
  ///
  /// media_kit 默认每路 32MiB，四路就是 128MiB 起；这是弱机上的主要内存旋钮。
  var multiPlayTileBufferSize = 16.obs;

  void setMultiPlayTileBufferSize(int e) {
    multiPlayTileBufferSize.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kMultiPlayTileBufferSize,
      e,
    );
  }

  /// 多开播放：是否显示各格的弹幕。关闭后各路弹幕的 item 集合保持为空。
  var multiPlayTileDanmaku = true.obs;

  void setMultiPlayTileDanmaku(bool e) {
    multiPlayTileDanmaku.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kMultiPlayTileDanmaku,
      e,
    );
  }

  /// 多开播放：批量入口默认预载几路（2~4）。
  ///
  /// 只影响「关注页勾选后批量多开」的入口；手动一路路加（[MultiPlaySession.addRoom]）
  /// 上限仍是 [kMultiPlayMaxTiles]，不受这个值约束。
  var multiPlayDefaultTiles = 4.obs;

  void setMultiPlayDefaultTiles(int e) {
    final clamped = e.clamp(kMultiPlayMinTiles, kMultiPlayMaxTiles);
    multiPlayDefaultTiles.value = clamped;
    LocalStorageService.instance.setValue(
      LocalStorageService.kMultiPlayDefaultTiles,
      clamped,
    );
  }

  var pipHideDanmu = true.obs;

  void setPIPHideDanmu(bool e) {
    pipHideDanmu.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kPIPHideDanmu, e);
  }

  /// 小窗锁定画面纵横比（默认开启）
  var pipLockAspect = true.obs;

  void setPipLockAspect(bool e) {
    pipLockAspect.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPipLockAspect,
      e,
    );
  }
  /// window Setting
  // 开屏自动最大化
  var windowMaxAuto = false.obs;
  void setWindowMaxAuto(bool e){
    windowMaxAuto.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kWindowMaxAuto, e);
  }

  var windowMaxState = false.obs;
  void setWindowMaxState(bool e){
    windowMaxState.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kWindowMaxState, e);
  }

  /// window小窗size
  var windowPipX = 0.0.obs;

  void setWindowPipX(double e) {
    windowPipX.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kWindowPipX, e);
  }

  var windowPipY = 0.0.obs;

  void setWindowPipY(double e) {
    windowPipY.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kWindowPipY, e);
  }

  var windowPipWidth = 320.0.obs;

  void setWindowPipWidth(double e) {
    windowPipWidth.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kWindowPipWidth, e);
  }

  var windowPipHeight = 180.0.obs;

  void setWindowPipHeight(double e) {
    windowPipHeight.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kWindowPipHeight, e);
  }

  var danmuTopMargin = 0.0.obs;

  void setDanmuTopMargin(double e) {
    danmuTopMargin.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuTopMargin, e);
  }

  var danmuBottomMargin = 0.0.obs;

  void setDanmuBottomMargin(double e) {
    danmuBottomMargin.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuBottomMargin, e);
  }

  /// 弹幕去重参数设置
  var danmuTextNormalization = true.obs;

  void setDanmuTextNormalization(bool e) {
    danmuTextNormalization.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuTextNormalization, e);
  }

  var danmuMaxFrequency = 3.obs;

  void setDanmuMaxFrequency(int e) {
    danmuMaxFrequency.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuMaxFrequency, e);
  }

  var danmuFrequencyControl = true.obs;

  void setDanmuFrequencyControl(bool e) {
    danmuFrequencyControl.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuFrequencyControl, e);
  }

  var danmuWindowMs = 15.obs;

  void setDanmuWindowMs(int e) {
    danmuWindowMs.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuWindowMs, e);
  }

  var bilibiliLoginTip = true.obs;

  void setBiliBiliLoginTip(bool e) {
    bilibiliLoginTip.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kBilibiliLoginTip, e);
  }

  var logEnable = false.obs;

  void setLogEnable(bool e) {
    logEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kLogEnable, e);
  }

  var firebaseEnable = true.obs;

  void setFirebaseEnable(bool e) {
    firebaseEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kFirebaseEnable, e);
  }

  var customPlayerOutput = false.obs;

  void setCustomPlayerOutput(bool e) {
    customPlayerOutput.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kCustomPlayerOutput, e);
  }

  var videoOutputDriver = "".obs;

  void setVideoOutputDriver(String e) {
    videoOutputDriver.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kVideoOutputDriver, e);
  }

  var audioOutputDriver = "".obs;

  void setAudioOutputDriver(String e) {
    audioOutputDriver.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kAudioOutputDriver, e);
  }

  var videoHardwareDecoder = "".obs;

  void setVideoHardwareDecoder(String e) {
    videoHardwareDecoder.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kVideoHardwareDecoder, e);
  }

  var videoDoubleBuffering = false.obs;

  void setVideoDoubleBuffering(bool e) {
    videoDoubleBuffering.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kVideoDoubleBuffering, e);
  }

  var enableRtxVsr = false.obs;

  void setEnableRtxVsr(bool e) {
    enableRtxVsr.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kEnableRtxVsr, e);
  }

  /// 音量均衡：不同平台/主播的响度差异大，用 loudnorm 归一化到目标 LUFS 拉平。
  /// 依赖 fork 的 libmpv 构建（feat/audio-filters，含 dynaudnorm/loudnorm），
  /// 若运行在未编译该滤镜的内核上会走"探测失败→自动关闭"流程。
  var volumeNormalize = true.obs;

  void setVolumeNormalize(bool e) {
    volumeNormalize.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kVolumeNormalize, e);
    // 通知当前播放器实时增删 af 滤波链，不必重进直播间
    EventBus.instance.emit(EventBus.kVolumeNormalizeChanged, e);
  }

  /// 音量均衡的目标响度（LUFS）。-16 为移动端流媒体惯例，觉得整体偏轻可调 -14/-12。
  var volumeNormalizeTargetLufs = (-16).obs;

  void setVolumeNormalizeTargetLufs(int e) {
    volumeNormalizeTargetLufs.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kVolumeNormalizeTargetLufs, e);
    // 目标变了要重建 af 滤波链，通知当前播放器即时生效。
    // 沿用 bool 负载：订阅方不读 payload，但事件名只有一个，别混入 int。
    EventBus.instance.emit(EventBus.kVolumeNormalizeChanged, volumeNormalize.value);
  }

  /// Stats 覆盖层后端："app" = Flutter 自绘浮层（默认，HDR 屏不会出现 mpv OSD 的亮度闪烁），
  /// "mpv" = mpv 内置 stats.lua（script-binding，需内核编入 Lua）。
  var osdBackend = "app".obs;

  void setOSDBackend(String e) {
    osdBackend.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kOSDBackend, e);
    // 通知当前播放器收尾：切到 mpv 时关掉自绘浮层，切回自绘时关掉 mpv 的 OSD。
    EventBus.instance.emit(EventBus.kOSDBackendChanged, e);
  }

  var autoUpdateFollowEnable = false.obs;

  void setAutoUpdateFollowEnable(bool e) {
    autoUpdateFollowEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kAutoUpdateFollowEnable, e);
  }

  var autoUpdateFollowDuration = 10.obs;

  void setAutoUpdateFollowDuration(int e) {
    autoUpdateFollowDuration.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kUpdateFollowDuration, e);
  }

  var updateFollowThreadCount = 4.obs;

  void setUpdateFollowThreadCount(int e) {
    updateFollowThreadCount.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kUpdateFollowThreadCount, e);
  }

  var followSnapshotEnable = false.obs;

  void setFollowSnapshotEnable(bool e) {
    followSnapshotEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kFollowSnapshotEnable, e);
  }

  var dormancyThreshold = 0.obs;

  void setDormancyThreshold(int e) {
    dormancyThreshold.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDormancyThreshold, e);
  }

  var playerForceHttps = false.obs;

  void setPlayerForceHttps(bool e) {
    playerForceHttps.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kPlayerForceHttps, e);
  }

  var douyinHlsFirst = false.obs;

  void setDouyinHlsFirst(bool e) {
    douyinHlsFirst.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDouyinHlsFirst, e);
  }

  var followSortMethod = SortMethod.watchDuration.obs;

  void setFollowSortMethod(SortMethod e) {
    followSortMethod.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kFollowSortMethod, e.storeValue);
  }

  /// 关注页分组视图折叠中的标签 id 集合。
  ///
  /// 默认值必须留在声明处、只在 `onInit` 里读存储 —— widget test 的假设置
  /// 跳过 `onInit`，构造期读 `LocalStorageService` 会让测试直接炸。
  final followCollapsedGroups = <String>[].obs;

  void setFollowCollapsedGroups(List<String> ids) {
    followCollapsedGroups.value = ids;
    LocalStorageService.instance.setValue(
        LocalStorageService.kFollowCollapsedGroups, ids.join(","));
  }

  // 关注样式是否卡片化
  //
  // ⚠️ **当前没有读取方**：关注页改成「上段卡片 + 下段紧凑行」的整合布局之后，
  // 原来那个「紧凑模式 / 卡片模式」二选一就不存在了，AppBar 里的「模式切换」
  // 菜单项也已移除（2026-09-15）。这里**刻意保留**字段、setter 与存储键
  // （`kFollowStyleNotGrid`）：一来老用户的取值不会被清掉，二来以后若要恢复
  // 「让用户选上段用卡片还是紧凑行」，改回来很便宜。
  var followStyleNotGrid = true.obs;

  void setFollowStyleNotGrid(bool e) {
    followStyleNotGrid.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kFollowStyleNotGrid, e);
  }

  // 隐藏不在线的关注
  var hideOfflineFollow = false.obs;

  void setHideOfflineFollow(bool e) {
    hideOfflineFollow.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kHideOfflineFollow, e);
  }

  // 隐藏快速取关按钮。初值与 [initData] 里的读取默认值必须一致（都是 false = 显示）。
  var hideRemoveFollowButton = false.obs;

  void setHideRemoveFollowButton(bool e) {
    hideRemoveFollowButton.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kHideRemoveFollow, e);
  }

  /// 保存关注列表快照
  FollowSnapshot? followSnapshot;

  Future setFollowSnapshot(FollowSnapshot followSnapshot) {
    return LocalStorageService.instance.setValue(LocalStorageService.kFollowSnapshot, followSnapshot);
  }
}
