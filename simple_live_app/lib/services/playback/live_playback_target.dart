/// 后台播放的系统媒体控制（通知栏 / 锁屏 / 耳机键）与「当前正在播的那一路」之间
/// 唯一的契约。
///
/// 为什么要有这一层：handler 属于 `services/`，实现者属于 `modules/live_room/`，
/// 而 `services/` 绝不 import `modules/`（会形成依赖环）。两边只共享这个抽象。
///
/// 实现者必须保证两条，因为通知的生命周期与播放器的生命周期**不同步**：
/// * getter 在播放器已释放之后也不许抛异常（摘除与释放之间总有一瞬）；
/// * 指令幂等，且在没有播放器时安全返回。
///
/// 只有直播间页面的主格（`isSecondaryTile == false`）实现并挂载它：多开时四路争
/// 同一条通知只会互相顶掉。
abstract interface class LivePlaybackTarget {
  /// 这一路在整个 app 里的稳定身份，用作媒体会话的 mediaId。
  String get playbackMediaId;

  /// 房间标题（通知与锁屏的第一行）。
  String get playbackTitle;

  /// 主播名（第二行）。
  String get playbackArtist;

  /// 直播平台名（B站 / 抖音 / …），走 album 字段，与主播名分开展示。
  String get playbackAlbum;

  /// 房间封面。拉不到（空串、防盗链）时返回 null，通知退化成纯文字。
  Uri? get playbackArtUri;

  /// 是否按直播处理（未开播时在轮播的那段录像算点播）。
  ///
  /// v1 **不**用它决定要不要发 duration：一旦发了 duration，Android 与 iOS 都会画出
  /// 可拖的进度条，而我们不推 position，那条会永远冻在 0:00。真要做进度，得同时
  /// 接上 `player.stream.position`。
  bool get playbackIsLive;

  /// 此刻是否在出声。
  bool get playbackPlaying;

  /// 此刻是否在缓冲（弱网时通知不能假装「在播」）。
  bool get playbackBuffering;

  /// 用户在通知/锁屏上按了播放。
  Future<void> playbackPlay();

  /// 用户按了暂停。
  Future<void> playbackPause();

  /// 用户按了停止：停声，并让通知与前者的展示位一起消失。
  Future<void> playbackStop();
}
