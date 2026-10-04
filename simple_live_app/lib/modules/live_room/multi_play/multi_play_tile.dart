import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_bar.dart';
import 'package:simple_live_app/modules/live_room/player/player_action_views.dart';
import 'package:simple_live_app/modules/live_room/player/player_actions.dart';
import 'package:simple_live_app/modules/live_room/player/player_controls.dart';
import 'package:simple_live_app/modules/live_room/player/player_fit.dart';

/// 多开网格里的一格：一路播放 + 它自己的弹幕 + 一条底部信息/控制条。
///
/// 不复用 `playerControls`：那套 OSD 有四十多个控件，摆在 240×135 的格子上既点不中
/// 也看不清。这里只留小格子上真能用的几件，其余收进 `⋮`——清单与桌面条带同源
/// （`resolvePlayerActions(host: tile)`），渲染也同源（`PlayerActionBar`）：同一个动作
/// 在格子和在条带里的图标、tooltip、执行路径都是同一份，不会再各写各的分叉。
/// 完整 OSD 仍然可以从聚焦格双击进全屏后使用。
///
/// 信息与控制分居两角、各用一个**自适应大小的胶囊遮罩**兜住（左下：序号+名字+换台；
/// 右下：平铺件 + `⋮`），中间不画遮罩——早期那版是一条横跨整幅画面的黑条，
/// 中间一大段纯装饰，既土又白占画面。整组随网格的显隐一起出现/隐藏，不做常驻。
class MultiPlayTile extends StatelessWidget {
  const MultiPlayTile({
    super.key,
    required this.page,
    required this.tile,
    required this.index,
    required this.focused,
    required this.chromeVisible,
    required this.onInteract,
  });

  /// 页面主格：全屏是窗口级操作，只能由它来开。
  final LiveRoomController page;

  /// 本格自己的 controller。
  final LiveRoomController tile;

  /// 在会话 slots 里的下标（0 = 主格，不可关闭）；显示为「第 N 路」。
  final int index;

  final bool focused;

  /// 是否显示底部信息条。由网格统一控制：鼠标在网格里动一下，四路一起出现，
  /// 停手几秒一起隐去。
  final bool chromeVisible;

  /// 本格被交互时通知网格——把「自动隐藏」的倒计时续上（打开菜单时尤其需要）。
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: AppStyle.radius8,
        border: Border.all(
          color: focused ? colorScheme.primary : Colors.white12,
          width: focused ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: Obx(_buildVideo)),
          Positioned.fill(child: _buildStates()),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                onInteract();
                page.multiPlay.focusSlot(index);
              },
              onLongPressStart: (d) async {
                // 长按＝换这一格（与格子信息胶囊里那颗 ▾ 同一份菜单内容）。
                // 走 `showFollowPickMenu`（长按点当锚点的 `showMenu`）而不是给 ▾ 那颗
                // 按钮加 GlobalKey：本 widget 是 StatelessWidget，键每次 build 都是新的，
                // `showButtonMenu().then` 会因重挂载把选中结果静默丢掉。
                onInteract();
                final user = await showFollowPickMenu(
                  context: context,
                  position: d.globalPosition,
                  entries: tile.multiPlay.buildSwitchEntries(),
                );
                if (user != null) {
                  pickFollowUser(tile, user);
                }
              },
              onDoubleTap: () {
                // 双击切换全屏，与单画面「双击视频」一致：进得去也出得来。
                // 之前只调 enterFullScreen，进了全屏再双击还是「进全屏」，
                // 于是只能靠 ESC 退出——和单画面割裂。
                //
                // 双击时 Flutter 会先派发一次 onTap（焦点已落在这一格），这里再显式
                // 设一次只是不依赖那个行为。
                page.multiPlay.focusSlot(index);
                if (page.fullScreenState.value) {
                  page.exitFull();
                } else {
                  page.enterFullScreen();
                }
              },
            ),
          ),
          // ⚠️ 隐藏时**不能**把这一层从树里摘掉：`PopupMenuButton`（信息胶囊里那颗 ▾）
          // 在菜单打开期间若被 unmount，`showButtonMenu` 的 `.then` 里有
          // `if (!mounted) return null`（popup_menu.dart），选中的结果会被静默丢弃——
          // 表现就是换台点了没反应。所以这里是「常挂 + IgnorePointer + 淡出」，
          // 不是条件移除。音量那颗浮在 Overlay 里的滑条也靠这条活着：胶囊淡掉了，
          // 它仍在原地可拖（见 `player_volume_action.dart` 的命中测试说明）。
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: IgnorePointer(
              ignoring: !chromeVisible,
              child: AnimatedOpacity(
                opacity: chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Row(
                  // 两个胶囊分居左右，中间的空白**不画遮罩**——早期那版是一条横跨
                  // 整幅画面的黑条，中间一大段纯装饰，既土又白占画面。
                  // 用 spaceBetween 而不是 Spacer：Spacer 会先按 flex 占掉一半，
                  // 窄格子下信息胶囊会被无谓地挤短。
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: _buildInfoPill(colorScheme)),
                    _buildControlsPill(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 左下角的信息胶囊：`① 主播名 ▾`。
  ///
  /// 遮罩只包住这一簇；名字用 `Flexible` 兜住（窄格子自动省略号），名字被挤到 0 也还
  /// 留得住序号牌与 ▾（实测这一簇最小 66 宽）。
  /// ⚠️ 宽度预算：接 renderer 后右胶囊若按桌面 36×36 的 chrome 实测 184 宽，240 宽的
  /// 格子（`kMultiPlayMinTileWidth`，四路 2×2 把窗口缩到下限正好落在这尺寸）里两胶囊
  /// 最小和 250 顶过 Row 的 224，名字挤成 0 后内层溢出；右胶囊改用紧凑密度（30×30，
  /// 实测 ~154）后 66+154=220 留得住余量，回归由 `test/player_action_bar_test.dart` 钉住。
  Widget _buildInfoPill(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: AppStyle.radius8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 序号与名字只是展示，必须包 IgnorePointer：`Text`（`RenderParagraph`）本身
          // 会参与命中测试，不包起来这一簇就成了死区，点它落不到正下方
          // 「点一下切焦点」的手势上（之前重构时把这层弄丢了，昵称就点不动了）。
          IgnorePointer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSlotBadge(colorScheme),
                const SizedBox(width: 6),
                Flexible(child: _buildName()),
              ],
            ),
          ),
          _buildSwitchButton(),
        ],
      ),
    );
  }

  /// 右下角的按钮胶囊：resolver 给的 tile 切片 + `⋮`，与桌面条带共用 renderer。
  ///
  /// `availableWidth` 恒给 infinity：tile 宿主平铺哪几件由 `_tierFor(tile)` 定死
  /// （core 件平铺、其余恒进 `⋮`），宽度不参与决策。用 `LayoutBuilder` 量实测宽反而是
  /// 错的——胶囊挂在无界的 Row 里，量到的 `maxWidth` 本来就是 infinity，绕一圈回到同一个
  /// 值，还多一次布局；换成有界宿主时又会把「按宽度收纳」这条静默打开。
  ///
  /// reactive 读取必须落在这个 `Obx` 的同步 builder 里：`qualites`/`playUrls` 是详情
  /// 加载完才 `assignAll` 的、`isVertical` 也在那时翻转，读在 `Obx` 之外就订阅不上，
  /// `⋮` 会一直停在「这一路没有清晰度/线路可选」那份旧清单。
  Widget _buildControlsPill() {
    return Obx(() {
      final layout = resolvePlayerActions(
        host: PlayerHost.tile,
        availableWidth: double.infinity,
        // 能不能关这一格由 resolver 决定（主格是页面本身，销不得），renderer 只接
        // onCloseTile：closeTile 出现在 bar 里，那颗 ✕ 才会被画出来。
        canCloseTile: index > 0,
        hasQuality: tile.hasMultipleQualities,
        hasLine: tile.hasMultipleLines,
        isVertical: tile.isVertical.value,
        // 触屏上音量颗的点击是「弹滑条」（没 hover），静音这个动作改由 `⋮` 里那行
        // muteTile 承担——所以清单要多带这一件。桌面不传，产物逐字不变。
        isTouch: !AppSettingsController.isDesktop,
      );
      return Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: AppStyle.radius8,
        ),
        child: PlayerActionBar(
          host: PlayerHost.tile,
          target: tile,
          page: page,
          // pick 画在左下信息胶囊里（▾ 紧挨昵称），这里滤掉免得一颗胶囊冒出两颗换台。
          bar: layout.bar.where((e) => e.id != PlayerActionId.pick).toList(),
          overflow: layout.overflow,
          // 紧凑密度（30×30 按钮 + 20 图标）：240 宽的格子（kMultiPlayMinTileWidth）里
          // 桌面 chrome 的五颗按钮会把两胶囊顶过底栏，溢出回归由
          // test/player_action_bar_test.dart 钉住；桌面条带调用点不传这颗，尺寸不变。
          compact: true,
          // 格子胶囊是无界 Row 的非 flex 孩子：hug 走 MainAxisSize.min，renderer 里
          // 那颗 `Spacer`（就是 Expanded）在无界宽度下会直接抛错。
          hug: true,
          onInteract: onInteract,
          // renderer 的 closeTile 那条臂只调 onCloseTile、不调 onInteract（它只管画那颗 ✕），
          // 所以续期在这里补上：旧的格子关闭按钮本来就是「先续期再关」，关掉这一格之后
          // 指针还在网格里，倒计时得从这次点击重新算。
          onCloseTile: () {
            onInteract();
            page.multiPlay.removeTile(tile);
          },
        ),
      );
    });
  }

  /// 序号圆牌。后面所有「第 N 路」的引用（换台菜单、侧栏跟随提示）都靠它对上号。
  Widget _buildSlotBadge(ColorScheme colorScheme) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: focused ? colorScheme.primary : Colors.white24,
        shape: BoxShape.circle,
      ),
      child: Text(
        "${index + 1}",
        style: TextStyle(
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w600,
          color: focused ? colorScheme.onPrimary : Colors.white,
        ),
      ),
    );
  }

  Widget _buildName() {
    return Obx(() {
      final name = tile.detail.value?.userName;
      return Text(
        (name == null || name.isEmpty) ? "第${index + 1}路" : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: Colors.white),
      );
    });
  }

  /// 昵称后的 ▾：换这一格播哪一路（菜单本体在 `FollowPickButton`，与单画面同源）。
  ///
  /// [FollowPickButton.target] 传本格 `tile`：`tile.multiPlay` 与 `page.multiPlay`
  /// 是同一个会话对象（副格由 `attachHostSession` 回填），所以数据源
  /// (`buildSwitchEntries`) 与换台落点 (`replaceTileRoom(tile, ...)`) 与内联实现等价。
  Widget _buildSwitchButton() {
    return FollowPickButton(
      target: tile,
      iconSize: 20,
      icon: const Icon(Icons.arrow_drop_down),
      // 紧凑样式取自 renderer 的同一来源（30×30/零内边距/白前景），不再在本文件
      // 手写一份复制品——那份手抄与 PlayerActionBar(compact: true) 的内部样式
      // 逐字段相同，正说明它不该再存在第二份。
      style: playerActionIconStyle(compact: true),
      // 菜单开着时把网格那几秒倒计时续上，避免底栏（连同这个入口）被隐藏
      onOpened: onInteract,
    );
  }

  Widget _buildVideo() {
    final settings = AppSettingsController.instance;
    // 订阅本格的覆盖值：它变了这格的外框比例要跟着重建（updateScaleMode 只改 state，
    // 初始参数不变的话、下一次重建又会回到旧值）。
    final fit = resolvePlayerFit(tile.effectiveScaleMode);
    return Video(
      key: tile.globalPlayerKey,
      controller: tile.videoController,
      pauseUponEnteringBackgroundMode: settings.playerAutoPause.value,
      resumeUponEnteringForegroundMode: settings.playerAutoPause.value,
      // 弹幕层必须在 controls 里：buildDanmuView 返回的是 Positioned.fill，
      // 直接当 controls 的返回值会因为不在 Stack 里而报错。
      controls: (state) => Stack(children: [buildDanmuView(state, tile)]),
      aspectRatio: fit.aspectRatio,
      fit: fit.fit,
      // 保持唤醒由主格那份负责，四路各开一次没有意义
      wakelock: false,
    );
  }

  /// 加载 / 未开播 / 加载失败三态。
  ///
  /// 副格不走 `SmartDialog.showLoading`（那是全局单例浮层，四路会互相顶掉），
  /// 所以加载态只能在格子里自己表达。
  Widget _buildStates() {
    return Obx(() {
      if (tile.loadError.value) {
        return _buildCenterLabel("加载失败", tile.error?.toString());
      }
      if (tile.detail.value == null) {
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
          ),
        );
      }
      if (!tile.liveStatus.value) {
        return _buildCenterLabel("未开播", null);
      }
      return const SizedBox.shrink();
    });
  }

  Widget _buildCenterLabel(String text, String? detail) {
    return Center(
      child: Padding(
        padding: AppStyle.edgeInsetsA8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
