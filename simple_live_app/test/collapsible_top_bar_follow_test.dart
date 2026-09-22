// 回归测试：关注页滑动收起顶栏 / 底栏。
//
// 底栏收起在 IndexedPage 顶层统一处理，所有 Tab 都生效；顶栏收起依赖每个
// Tab 自己的 CollapsibleTopBarScaffold。本测试锁住关注页的**两件事**：
//
// 1. 收起生效：同步模式跟手位移、即时模式动画收起，两种模式下顶栏与内容区
//    都随滑动上移 / 复原；
// 2. 收起必须是纯绘制：过程中内容区（页面最重的滚动列表）的**尺寸恒定**。
//    旧实现用 `Align(heightFactor:)` 真实压缩顶栏高度，每帧都会触发父级重排
//    （列表视口尺寸变化 + 栏内 Material 重算），同步模式在安卓上就是掉帧的来源。
//    一旦有人把收起改回「改布局」，这里会立刻失败。
//
// 假设置 / 假数据源 / 页面泵取在 `follow_test_harness.dart`，与分组视图测试共用。
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'follow_test_harness.dart';

void main() {
  setUp(() {
    Get.testMode = true;
  });

  testWidgets('同步模式：顶栏跟手收起，且内容区尺寸恒定（不重排）', (tester) async {
    final indexed = await pumpIndexed(tester);
    await gotoFollowPage(tester, indexed);

    final grid = followGrid(tester);
    final barSlotSize = tester.getSize(followBar(tester));
    final gridSize = tester.getSize(grid);
    final gridTop = tester.getTopLeft(grid).dy;
    final barTop = followBarTitleTop(tester);
    // 列表视口尺寸 / 滚动范围：旧实现每帧改栏高 ⇒ 视口尺寸每帧变 ⇒ 滚动位置
    // 被反复校正，表现为拖动时"抽动"。这里钉死收起全程这两项都不变。
    final position = Get.find<FollowUserController>().scrollController.position;
    final viewport = position.viewportDimension;
    final maxExtent = position.maxScrollExtent;

    expect(indexed.barOffset.value, 0, reason: '初始应完全展开');

    // 分多帧慢慢拖动，逐帧检查：内容区尺寸恒定 + 顶栏位移严格等于累计偏移
    for (var i = 0; i < 4; i++) {
      await tester.drag(grid, const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getSize(grid),
        gridSize,
        reason: '第 $i 帧：收起过程中内容区尺寸不得变化（变化=每帧重排）',
      );
      expect(
        tester.getSize(followBar(tester)),
        barSlotSize,
        reason: '第 $i 帧：顶栏槽位高度必须恒定，否则父级会跟着重排',
      );
      expect(
        position.viewportDimension,
        viewport,
        reason: '第 $i 帧：列表视口尺寸不得随收起变化（否则滚动位置被反复校正）',
      );
      expect(
        position.maxScrollExtent,
        maxExtent,
        reason: '第 $i 帧：滚动范围不得随收起变化',
      );
      expect(
        barTop - followBarTitleTop(tester),
        moreOrLessEquals(indexed.barOffset.value, epsilon: 0.01),
        reason: '第 $i 帧：顶栏位移必须与累计偏移严格一致（跟手）',
      );
      expect(
        gridTop - tester.getTopLeft(grid).dy,
        moreOrLessEquals(indexed.barOffset.value, epsilon: 0.01),
        reason: '第 $i 帧：内容区必须与顶栏同步上移',
      );
    }

    expect(indexed.barOffset.value, greaterThan(0),
        reason: '同步模式下拖动必须累计 barOffset');

    // 拖足够远：完全收起，顶栏整条移出、内容区恰好上移一个顶栏高度
    await tester.drag(grid, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 16));
    expect(indexed.barOffset.value, IndexedController.maxBarOffset,
        reason: '拖够距离后应完全收起');
    expect(barTop - followBarTitleTop(tester),
        moreOrLessEquals(IndexedController.maxBarOffset, epsilon: 0.01));
    expect(gridTop - tester.getTopLeft(grid).dy,
        moreOrLessEquals(IndexedController.maxBarOffset, epsilon: 0.01));
    expect(tester.getSize(grid), gridSize, reason: '拖动结束后内容区尺寸仍应恒定');

    // 反向拖回：顶栏与内容区一起复原
    await tester.drag(grid, const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(indexed.barOffset.value, 0);
    expect(followBarTitleTop(tester), moreOrLessEquals(barTop, epsilon: 0.01));
    expect(tester.getTopLeft(grid).dy, moreOrLessEquals(gridTop, epsilon: 0.01));

    // 换页会让 easy_refresh 排零延时计时器，跑完再结束
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('即时模式：顶栏动画收起、内容区上移，尺寸同样恒定', (tester) async {
    final indexed = await pumpIndexed(tester, hideType: 0);
    await gotoFollowPage(tester, indexed);

    final grid = followGrid(tester);
    final barSlotSize = tester.getSize(followBar(tester));
    final gridSize = tester.getSize(grid);
    final gridTop = tester.getTopLeft(grid).dy;
    final barTop = followBarTitleTop(tester);

    await tester.drag(grid, const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 100));

    expect(indexed.showTopBar.value, false,
        reason: '即时模式向上滑应置 showTopBar=false');
    expect(tester.getSize(grid), gridSize, reason: '收起动画同样不得改变内容区尺寸');

    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 完全收起：顶栏整体移出槽位（视觉上不可见），内容区上移一个 toolbar 高度
    expect(
      followBarTitleTop(tester),
      lessThanOrEqualTo(barTop - barSlotSize.height + 0.5),
      reason: '顶栏必须完全移出槽位',
    );
    expect(
      tester.getTopLeft(grid).dy,
      moreOrLessEquals(gridTop - barSlotSize.height, epsilon: 0.5),
      reason: '内容区应恰好上移一个顶栏高度',
    );

    // 换页会让 easy_refresh 排零延时计时器，跑完再结束
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('底栏收起不改布局：悬浮胶囊样式下内容区尺寸也恒定', (tester) async {
    final indexed = await pumpIndexed(tester, navStyle: 1);
    await gotoFollowPage(tester, indexed);

    final grid = followGrid(tester);
    final gridSize = tester.getSize(grid);

    await tester.drag(grid, const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 16));

    expect(indexed.barOffset.value, greaterThan(0));
    expect(tester.getSize(grid), gridSize,
        reason: '底栏收起不得改变 body 约束（否则每帧重排整页）');

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('同步模式：滚轮滚动同样驱动顶/底栏收起（桌面端与拖动一致）',
      (tester) async {
    final indexed = await pumpIndexed(tester);
    await gotoFollowPage(tester, indexed);
    // 排空 refreshOnStart 的收起动画，否则它会 hold 住列表、吃掉第一次 animateTo
    await settle(tester);

    final c = Get.find<FollowUserController>();
    final barTop = followBarTitleTop(tester);

    Future<void> wheel(double dy) async {
      // 固定悬停在视口中部的列表内容上（滚动前后都命中外层列表）
      final pointer = TestPointer(99, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(200, 450)));
      await tester.pump();
      await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    await wheel(40);
    expect(c.scrollController.position.pixels, greaterThan(0),
        reason: '前置条件：滚轮确实滚动了外层列表');
    expect(indexed.barOffset.value, greaterThan(0),
        reason: '滚轮向下必须驱动同步模式收起：滚轮走 animateTo，'
            '通知的 dragDetails 为 null，曾被「惯性不驱动」的过滤一并挡掉');

    await wheel(300);
    expect(indexed.barOffset.value, IndexedController.maxBarOffset,
        reason: '连续滚动后应能完全收起');
    expect(barTop - followBarTitleTop(tester),
        moreOrLessEquals(IndexedController.maxBarOffset, epsilon: 0.01),
        reason: '顶栏应实际让出一个 toolbar 高度（底部内容不再被裁半行）');

    // 反向滚：顶栏回来
    await wheel(-500);
    expect(indexed.barOffset.value, 0);

    await tester.pump(const Duration(milliseconds: 400));
  });
}
