import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/models/db/follow_user.dart';

FollowUser _user({
  String remark = '',
  bool showRemarkAsName = true,
}) =>
    FollowUser(
      id: 'huya_123',
      roomId: '123',
      siteId: 'huya',
      userName: '原名',
      face: '',
      addTime: DateTime(2026),
      remark: remark,
      showRemarkAsName: showRemarkAsName,
    );

void main() {
  group('显示为昵称', () {
    test('开启且备注非空时用备注替换原名', () {
      expect(_user(remark: '昵称').displayName, '昵称');
    });

    test('关闭时始终显示原名', () {
      expect(_user(remark: '昵称', showRemarkAsName: false).displayName, '原名');
    });

    test('备注为空或全空白时回退原名', () {
      expect(_user(remark: '').displayName, '原名');
      expect(_user(remark: '   ').displayName, '原名');
    });

    test('旧 JSON 没有开关字段时默认开启，保持既有备注显示行为', () {
      final user = FollowUser.fromJson({
        'id': 'huya_123',
        'roomId': '123',
        'siteId': 'huya',
        'userName': '原名',
        'face': '',
        'addTime': '2026-01-01T00:00:00.000',
        'remark': '昵称',
      });
      expect(user.showRemarkAsName, isTrue);
      expect(user.displayName, '昵称');
    });

    test('JSON 往返保留开关状态', () {
      final user = _user(remark: '昵称', showRemarkAsName: false);
      final restored = FollowUser.fromJson(user.toJson());
      expect(restored.showRemarkAsName, isFalse);
      expect(restored.displayName, '原名');
    });
  });
}
