import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils/extensions/duration_2_str_utils.dart';
import 'package:simple_live_app/models/db/history.dart';

import 'db_service.dart';

/// 单个直播间的观看计时单元：一个累计基线 + 一个 [Stopwatch]。
///
/// 纯算术、无 IO、无平台依赖，可在 Dart VM 单测里直接跑（分层与
/// `PipAspectCalculator` 一致：算术收敛在纯单元，读写留在 [HistoryService] 薄层）。
/// 多开播放时每个房间各持一个，取代原来「全 app 共用一个 Stopwatch、
/// 谁最后写入谁赢」的做法。
class RoomWatchClock {
  RoomWatchClock({Duration baseline = Duration.zero}) : _baseline = baseline;

  Duration _baseline;
  final Stopwatch _stopwatch = Stopwatch();

  bool get isRunning => _stopwatch.isRunning;

  /// 本次会话开始后已走过的时长。
  Duration get elapsed => _stopwatch.elapsed;

  /// 累计观看时长 = 本次会话前已落盘的时长（[_baseline]）+ 本次会话已走时长。
  Duration get total => _baseline + _stopwatch.elapsed;

  void start() {
    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }
  }

  /// 把「已落盘的时长」推进为新基线并归零计时（表继续走）。
  ///
  /// 每次落盘后都必须调用：原实现每次落盘都把「基线 + Stopwatch 全程」重新累加进
  /// syncDuration，而 Stopwatch 并不复位，于是 2 分钟定时器 / 换房间 / 退出三条路径
  /// 每触发一次就多算一遍观看时长。推进基线后 [total] 单调不减、重复落盘不重复计数。
  ///
  /// 注意这里只 `reset()`（清零但不改运行状态），不能 `stop()`——落盘每两分钟发生
  /// 一次，停表会让观看时长在第一次自动保存后就冻住。
  void commit() {
    _baseline = total;
    _stopwatch.reset();
  }

  /// 重进同一房间：保留累计时长，只把「本次会话」的计时归零。
  ///
  /// 同样只 reset 不停表：时钟只要还在 `HistoryService` 的表里就应该一直在走
  /// （只有 `stop(roomId:)` 会摘掉它）。若顺手停表，`reset` 与 `addHistory → start`
  /// 的先后顺序（`loadData` 不 await，两种顺序都会发生）就会决定它是否还在计时。
  void rewind(Duration baseline) {
    _baseline = baseline;
    _stopwatch.reset();
  }
}

class HistoryService extends GetxService {
  static HistoryService get instance => Get.find<HistoryService>();

  //两分钟自动保存一次，防止用户直接关闭app，丢失数据
  final _saveInterval = const Duration(minutes: 2);

  /// 定时器，全 app 只建一个；最后一个房间停止计时时取消。
  Timer? _timer;

  /// 正在计时的房间：id（`${siteId}_${roomId}`）→ 历史记录与计时单元。
  final Map<String, History> _histories = {};
  final Map<String, RoomWatchClock> _clocks = {};

  /// 开始/继续计时。
  ///
  /// 幂等：刷新、重进同一房间都会再走一次 `loadData → addHistory`，这里必须复用
  /// 已有计时单元。原实现每次调用都会重新读一遍基线（让计时翻倍）并新建一个
  /// 2 分钟定时器（旧定时器不取消，泄漏）。
  void start(History history) {
    final exist = _clocks[history.id];
    if (exist != null) {
      exist.start();
      return;
    }
    var record = DBService.instance.getHistory(history.id);
    if (record == null) {
      record = history;
      DBService.instance.addOrUpdateHistory(record);
    }
    _histories[history.id] = record;
    _clocks[history.id] = RoomWatchClock(baseline: record.duration)..start();
    _timer ??= Timer.periodic(_saveInterval, (timer) => _saveAll());
  }

  /// 重置单个房间的计时（切换房间用）。
  ///
  /// 累计时长保留为基线，只把「本次会话」的计时归零——原实现同时清了基线和全 app
  /// 的当前房间，多开时会把别的房间一起搞乱。
  ///
  /// 房间尚未登记时也会登记：`resetRoom` 里 `loadData()` 是不 await 的，
  /// 本方法与随后的 `addHistory → start` 顺序不确定，两条路都必须能独立建表。
  void reset(String roomId) {
    _save(roomId);

    final clock = _clocks[roomId];
    if (clock != null) {
      clock.rewind(clock.total);
      return;
    }
    final record = DBService.instance.getHistory(roomId);
    if (record == null) {
      return;
    }
    _histories[roomId] = record;
    _clocks[roomId] = RoomWatchClock(baseline: record.duration);
    _timer ??= Timer.periodic(_saveInterval, (timer) => _saveAll());
  }

  /// 停止计时。
  ///
  /// - [roomId] 非空：只落盘并摘除该房间；最后一个房间移除时取消定时器。
  /// - [roomId] 为空：落盘并摘除全部房间（整个直播间页退出时的兜底）。
  void stop({String? roomId}) {
    if (roomId != null) {
      _save(roomId);
      _histories.remove(roomId);
      _clocks.remove(roomId);
      if (_clocks.isEmpty) {
        _cancelTimer();
      }
      return;
    }
    for (final id in _clocks.keys.toList()) {
      _save(id);
    }
    _histories.clear();
    _clocks.clear();
    _cancelTimer();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _saveAll() {
    for (final id in _clocks.keys.toList()) {
      _save(id);
    }
  }

  /// 落盘一个房间的增量并推进其基线；未登记的房间直接返回。
  void _save(String roomId) {
    final clock = _clocks[roomId];
    final record = _histories[roomId];
    if (clock == null || record == null) {
      return;
    }
    final elapsed = clock.elapsed;
    record
      ..watchDuration = clock.total.toHMSString()
      ..syncDuration = record.syncDuration + elapsed.inSeconds
      ..updateTime = DateTime.now();
    DBService.instance.addOrUpdateHistory(record);
    EventBus.instance.emit(Constant.kUpdateFollow, record);
    Log.i("${record.id} 已观看时间：${clock.total.toHMSString()} 本次增加：${elapsed.toHMSString()}");
    clock.commit();
  }

  // 获取历史记录中存储的累计观看时长
  int getHistoryDurationSec({required String followUserId}) {
    var historyWatchDurationSec = 0;
    History? history = DBService.instance.getHistory(followUserId);
    historyWatchDurationSec = history?.watchDuration?.toDuration().inSeconds ?? 0;
    return historyWatchDurationSec;
  }

  // history crud
  History? getHistory(String id) {
    return DBService.instance.getHistory(id);
  }

  Future<void> addOrUpdateHistory(History history) async {
    await DBService.instance.addOrUpdateHistory(history);
  }

  Future<void> delHistory(String id) async {
    await DBService.instance.delHistory(id);
  }

  List<History> getHistories() {
    return DBService.instance.getHistories();
  }

  Future<void> historyClear() async {
    await DBService.instance.historyBox.clear();
  }
}
