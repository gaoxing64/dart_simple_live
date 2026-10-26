// “设置分组”对话框回归：内容必须真实渲染出分组勾选项，而不是 GetX
// “improper use” 之后的灰色 ErrorWidget；勾选保存后行内胶囊同步更新。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/widgets/follow_member_row.dart';
import 'package:simple_live_app/widgets/group_badge.dart';
import 'follow_test_harness.dart';

FollowUser _u(String name, {int live = 1}) => FollowUser(
      id: 'huya_$name',
      roomId: 'r-$name',
      siteId: 'huya',
      userName: name,
      face: '',
      addTime: DateTime(2024),
    )..liveStatus.value = live;

Finder rowOf(String name) => find.ancestor(of: find.text(name), matching: find.byType(FollowMemberRow));

void main() {
  setUp(() => Get.testMode = true);

  testWidgets('设置分组 dialog 正常渲染并可保存', (tester) async {
    final svc = FakeFollowService(
      users: [_u('甲', live: 2), _u('乙')],
      tags: [
        FollowUserTag(id: 'a0', tag: 'CS解说', userId: ['huya_甲']),
        FollowUserTag(id: 'a1', tag: 'LOL解说', userId: ['huya_乙']),
      ],
    );
    final indexed = await pumpIndexed(tester, followService: svc);
    await gotoFollowPage(tester, indexed);
    await settle(tester);
    // 新规则：分组标签只在选中项上显示，先选中再验证保存后的胶囊更新。
    Get.find<FollowUserController>().toggleSelected('huya_甲');
    await settle(tester);

    await tester.longPress(rowOf('甲'));
    await settle(tester);
    await tester.tap(find.byTooltip('设置分组'));
    await settle(tester);

    // 修复前这里是 0：dialog 内容被 GetX 错误替换成灰色 ErrorWidget。
    expect(find.byType(CheckboxListTile), findsNWidgets(2));

    // 勾上第二个分组（LOL解说）再保存 → 甲的胶囊变成 CS解说 +1
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pump();
    await tester.tap(find.byTooltip('保存'));
    await settle(tester);
    final jiaBadge = find.descendant(of: rowOf('甲'), matching: find.byType(GroupBadge));
    expect(find.descendant(of: jiaBadge, matching: find.text('CS解说')), findsOneWidget);
    expect(find.descendant(of: jiaBadge, matching: find.text('+1')), findsOneWidget);
    await settleEnd(tester);
  });
}