// 屏幕常亮引用计数的回归测试。
//
// 背景：WakelockPlus 是进程级全局开关，而直播间是多开的。旧实现「谁起播谁
// enable、谁结束/暂停谁 disable」，多开时断流或关掉一路会把其余路的常亮
// 一起灭掉；单开时断线重连的空窗也足以让系统熄屏。ScreenAwakeService 把
// 语义改成按路持有，这里锁住三条不变量：
//   1. 多持有者时释放其中一个，常亮保持开启；
//   2. 最后一个持有者释放，才真正关闭；
//   3. 同一持有者重复 acquire 不重复计数；release 幂等。
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/screen_awake_service.dart';

void main() {
  late List<bool> toggleCalls;
  late ScreenAwakeService service;

  ScreenAwakeService build() {
    toggleCalls = [];
    return ScreenAwakeService(toggle: (enable) async {
      toggleCalls.add(enable);
    });
  }

  test('多开：释放其中一路，其余路保持常亮', () {
    service = build();
    final tileA = Object();
    final tileB = Object();

    service.acquire(tileA, reason: 'playing');
    service.acquire(tileB, reason: 'playing');
    expect(service.holderCount, 2);
    expect(service.enabled, true);
    expect(toggleCalls, [true], reason: '两个持有者只 enable 一次');

    service.release(tileA);
    expect(service.holderCount, 1);
    expect(service.enabled, true, reason: '还有一路在播，常亮不能灭');
    expect(toggleCalls, [true], reason: '没有多余的开关调用');
  });

  test('最后一个持有者释放才真正熄灭', () {
    service = build();
    final tileA = Object();
    final tileB = Object();

    service.acquire(tileA);
    service.acquire(tileB);
    service.release(tileB);
    service.release(tileA);

    expect(service.holderCount, 0);
    expect(service.enabled, false);
    expect(toggleCalls, [true, false]);
  });

  test('同一持有者重复 acquire 不重复计数；release 幂等', () {
    service = build();
    final tile = Object();

    service.acquire(tile, reason: 'playing');
    service.acquire(tile, reason: 'playbackPlay');
    expect(service.holderCount, 1);
    expect(toggleCalls, [true]);

    service.release(tile);
    service.release(tile);
    expect(service.holderCount, 0);
    expect(toggleCalls, [true, false], reason: '重复 release 不产生额外开关调用');
  });

  test('releaseAll 清空全部持有者并熄灭', () async {
    service = build();
    service.acquire(Object());
    service.acquire(Object());

    await service.releaseAll();

    expect(service.holderCount, 0);
    expect(service.enabled, false);
    expect(toggleCalls, [true, false]);
  });

  test('从未持有过时 releaseAll 不发开关调用', () async {
    service = build();

    await service.releaseAll();

    expect(toggleCalls, isEmpty);
    expect(service.enabled, false);
  });
}
