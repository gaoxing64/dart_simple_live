import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

/// 守住「换台不泄漏」的前提：每格的身份不能随房间变。
///
/// 旧实现用 `"multi_${site.id}_$roomId"` 当 GetX 注册 tag；换台会改掉它的值，而实例
/// 仍注册在旧 tag 下，`Get.delete` 静默失败 → 那一格的播放器与弹幕 WS 泄漏且还在出声。
void main() {
  group('多开每格的身份', () {
    test('tag 与房间无关：改了房间 tag 不变、两格不重号', () {
      final sites = Sites.allSites.values.toList();
      final a = LiveRoomController(pSite: sites.first, pRoomId: "1");
      final b = LiveRoomController(pSite: sites.first, pRoomId: "1");

      final tagA = a.getxTag;
      expect(tagA, isNot(b.getxTag), reason: '同一房间的两格也必须各有各的 tag');

      final historyBefore = a.historyId;
      // 模拟换台：房间换了
      a.rxSite.value = sites[1];
      a.rxRoomId.value = "2";

      expect(a.historyId, isNot(historyBefore), reason: '房间派生的 id 本来就会变');
      expect(a.getxTag, tagA, reason: '身份必须原地不动，否则销不掉');
    });
  });
}