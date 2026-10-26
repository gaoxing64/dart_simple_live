// 回归测试：FollowService.reorderFollowTag（分组拖拽调序的真实实现）。
//
// 踩过的坑：旧实现把 item 先插回列表、再取 `followTagList[insertAt]` 当右邻居
// —— 那个“邻居”就是 item 自己。向下拖动时 generateKeyBetween(大, 小) 直接抛
// 异常，followTagList 停在“内存已挪位、未落库、未按 id 排序”的坏状态；
// 下一次调序再在坏列表上算 key，可能算出与既有标签相同的 id，
// DB put 覆盖掉另一个分组 —— 组从“分组管理”里消失，成员身上的标签字符串还在。
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';

/// 内存版 tagBox：只覆盖调序链路用到的方法。
class _FakeDBService extends DBService {
  final box = <String, FollowUserTag>{};

  @override
  Future<void> updateFollowTag(FollowUserTag followTag) async {
    box[followTag.id] = followTag;
  }

  @override
  Future deleteFollowTag(String id) async {
    box.remove(id);
  }

  @override
  List<FollowUserTag> getFollowTagList() => box.values.toList();
}

/// 被测对象用真实现；只掐掉读 Hive 的 onInit。
class _LiveFollowService extends FollowService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.reset();
    Get.put<DBService>(_FakeDBService());
    Get.put<FollowService>(_LiveFollowService());
  });

  tearDown(() => Get.reset());

  void seed() {
    final svc = FollowService.instance;
    svc.followTagList.assignAll([
      FollowUserTag(id: 'a0', tag: 'X', userId: []),
      FollowUserTag(id: 'a1', tag: 'Y', userId: []),
      FollowUserTag(id: 'a2', tag: 'Z', userId: []),
    ]);
    final db = Get.find<DBService>() as _FakeDBService;
    db.box
      ..clear()
      ..addEntries(svc.followTagList.map((t) => MapEntry(t.id, t)));
  }

  List<String> ids() =>
      FollowService.instance.followTagList.map((t) => t.id).toList();

  void expectStrictlyIncreasing() {
    final list = ids();
    for (var i = 0; i < list.length - 1; i++) {
      expect(list[i].compareTo(list[i + 1]) < 0, isTrue,
          reason: 'id 必须严格递增（排序不变量），实际：$list');
    }
  }

  test('向下调序：不抛异常、顺序正确、三个组都还在', () {
    seed();
    FollowService.instance.reorderFollowTag(0, 2); // X 挪到末尾
    expect(FollowService.instance.followTagList.map((t) => t.tag),
        ['Y', 'Z', 'X']);
    expectStrictlyIncreasing();
    expect((Get.find<DBService>() as _FakeDBService).box.length, 3,
        reason: '落库记录数不得变少（覆盖丢组）');
  });

  test('向上调序：正常', () {
    seed();
    FollowService.instance.reorderFollowTag(2, 0); // Z 挪到最前
    expect(FollowService.instance.followTagList.map((t) => t.tag),
        ['Z', 'X', 'Y']);
    expectStrictlyIncreasing();
    expect((Get.find<DBService>() as _FakeDBService).box.length, 3);
  });

  test('连续调序不产生重复 id（覆盖丢组的场景）', () {
    seed();
    FollowService.instance
      ..reorderFollowTag(0, 2)
      ..reorderFollowTag(2, 0)
      ..reorderFollowTag(0, 1);
    expect(ids().toSet().length, 3, reason: 'id 不得相撞：${ids()}');
    expectStrictlyIncreasing();
    expect((Get.find<DBService>() as _FakeDBService).box.length, 3);
    expect(FollowService.instance.followTagList.map((t) => t.tag).toSet(),
        {'X', 'Y', 'Z'});
  });
}
