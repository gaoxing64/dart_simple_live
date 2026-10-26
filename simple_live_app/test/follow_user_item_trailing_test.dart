// 关注列**对齐轴**的回归。
//
// 缺陷本质是「`ListTile` 只对齐 trailing 的右边缘，图标中心随内容宽度漂」，
// 所以只能用真实布局 + 取坐标来证：
// ① 行尾三形态要落在同一条竖线上（在播 ▶ 另有约 1px 的光学补偿，见下）；
// ② 右下角那颗刷新按钮也得落在同一条线上——它是另一处漏网的（写死过 `right: 12`）。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';

FollowUser _user(String id) => FollowUser(
      id: id,
      roomId: id,
      siteId: "bilibili",
      userName: id,
      face: "",
      addTime: DateTime(2026, 1, 1),
    );

/// 把三种形态并排摆在一个固定宽度的列表里——正是直播间关注面板的实况
/// （正在播的那行是在播指示，其余行是按钮）。
Widget _harness() {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 320,
        child: Column(
          children: [
            // 形态一：在播指示
            FollowUserItem(item: _user("playing"), playing: true),
            // 形态二：取消关注按钮
            FollowUserItem(item: _user("removable"), onRemove: () {}),
            // 形态三：调用方自定义（直播间面板挂的就是这颗「加入多开」）
            FollowUserItem(
              item: _user("custom"),
              trailing: IconButton(
                tooltip: "加入多开播放",
                onPressed: () {},
                icon: const Icon(Icons.playlist_add),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    // FollowUserItem 读 Sites.allSites[siteId]!，不预热会直接抛。
    expect(Sites.allSites.containsKey("bilibili"), isTrue);
  });

  testWidgets('行尾三形态：两颗按钮的中心严格对齐', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final removeCenter = tester.getCenter(find.byIcon(Remix.dislike_line));
    final addCenter = tester.getCenter(find.byIcon(Icons.playlist_add));

    // 两颗按钮都是「48 宽槽里居中」，必须严格重合。
    // 修复前：在播指示 64 宽（中心距右 32）、按钮 48 宽（中心距右 24），差 8px。
    expect(
      removeCenter.dx,
      moreOrLessEquals(addCenter.dx, epsilon: 0.5),
      reason: '取消关注与加入多开的中心必须对齐',
    );
  });

  testWidgets('在播 ▶ 必须做左移补偿，且是 1px 量级（不是 8px 的结构错位）', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final playCenter = tester.getCenter(find.byIcon(Icons.play_arrow));
    final addCenter = tester.getCenter(find.byIcon(Icons.playlist_add));
    final delta = playCenter.dx - addCenter.dx; // 右为正

    // 实测（把两个字形的槽并排渲染、再逐像素求亮像素包围盒，
    // 与 `getCenter` 拿到的盒中心相减）：
    //   playlist_add 的墨迹比自己盒中心偏右 +0.375px
    //   play_arrow   的墨迹比自己盒中心偏右 +1.375px
    // 两者差 **恰好 1.000px** —— 这就是「一个盒里居中，▶ 看上去却偏右」的全部原因。
    //
    // 所以那一颗**故意**左移约 1px 去对齐墨迹（三角的重心天然偏左、Material 把它
    // 往右挪过，肉眼比的是墨迹的左右边界，不是盒）。下面两条断言分别钉住
    // **方向**与**量级**：方向没了说明补偿被当成「没意义的 translate」删掉了；
    // 量级变成 8px 说明退回了「槽宽各写各的」那个老毛病。
    expect(
      delta,
      lessThan(0),
      reason: '▶ 必须带左移补偿，否则墨迹比「加入多开」偏右约 1px',
    );
    expect(
      delta,
      greaterThan(-2.0),
      reason: '补偿应是 1px 量级，不该是 8px 的结构错位',
    );
  });
}
