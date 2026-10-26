# 后台播放（Android / iOS）与系统媒体控制

## 目标

设置 → 直播间设置 → 播放器 →「后台播放」（**默认关闭**，仅移动端显示这一行）。
打开后：切到后台、锁屏、熄屏都继续出声，并在通知栏 / 锁屏 / 耳机媒体键上提供
播放-暂停与停止。

## 先纠正一个容易误判的前提

在这之前**并不是「后台就不播」**。`playerAutoPause`（「进入后台自动暂停」）默认 `false`，
media_kit_video 的 `Video` 那两个 `pauseUponEnteringBackgroundMode` /
`resumeUponEnteringForegroundMode` 因此都是 false，app 自己从不在切后台时暂停。
缺的是**系统层的保障**：

| 平台 | 改前状态 |
|---|---|
| Android | manifest 里连一个 `<service>` 都没有：无前台服务、无 `MediaSession`、无 `WAKE_LOCK`、无音频焦点。targetSdk 37 下进程随时会被挂起或回收；别的 app 一出声就与我们混音 |
| iOS | `Info.plist` **已**声明 `UIBackgroundModes: [audio]`（第 55-58 行），但没有任何地方把 `AVAudioSession` 切到 `playback` 类别并 `setActive`——那个 plist 键只说明「系统允许」，真正把会话维持在后台的是类别 |

## 接线

出声的自始至终是 media_kit 的 libmpv 播放器；`audio_service` 只是一块**投影面**。

```
LiveRoomController  ──implements──▶  LivePlaybackTarget（抽象，services 层）
      │  player.stream.playing/buffering/completed 每次跳一下
      ▼
  syncBackgroundPlayback()   ← 唯一入口，幂等
      │  attach(this) / detach(this)
      ▼
LivePlaybackAudioHandler（BaseAudioHandler，跑在主 isolate）
      │  mediaItem.add(...) / playbackState.add(...)
      ├──▶ Android：前台服务 + 通知 + MediaSession
      └──▶ iOS：MPNowPlayingInfoCenter + MPRemoteCommandCenter
LiveAudioSession（audio_session）── iOS 类别 playback / Android requestAudioFocus
                                    中断与拔耳机也只有这里能拿到
```

`LivePlaybackTarget` 存在的理由是切断依赖环：handler 属于 `services/`，实现者属于
`modules/live_room/`，而 `services/` 绝不 import `modules/`。

副格（`isSecondaryTile == true`）永不挂载：多开时四路争同一条通知只会互相顶掉。

## 三条已核过源码的事实（不是文档转述）

`audio_service 0.18.19`，直接读 pub cache 里的包：

1. **它不管音频焦点，也从不 `configure()` 音频会话。** 全包 grep 没有任何
   `requestAudioFocus` / `ACTION_AUDIO_BECOMING_NOISY`；对 `audio_session` 的唯一使用是
   在**已废弃**的 `onStop()` 里 `setActive(false)`，而我们走新 API 覆写 `stop()`，
   那条路不会被触发。⇒ 焦点、中断、拔耳机、iOS 类别，全由 `LiveAudioSession` 自己接。
2. **`AudioHandler.stop()` 的默认实现只把 `processingState` 改成 idle，不动 `playing`。**
   ⇒ 若直接 `super.stop()`，通知会停在「正在播放」的假象上，而 idle 状态没有任何东西
   能再把它改回来。所以这里用 `_publishIdle()` 显式落 `playing: false`。
3. **`AudioServiceActivity` 只覆写 `provideFlutterEngine()`**，没有任何生命周期/按键覆写。
   ⇒ `MainActivity` 换父类不影响 `floating` 那套 PiP（仍列为必测项，见下）。

另外 `AudioServiceConfig` 里有个硬 assert：
`!androidNotificationOngoing || androidStopForegroundOnPause` —— 「通知不可划掉」必须与
「暂停时降级前台服务」同时使用。Android 侧 `AudioService` 进播放态时会
`acquireWakeLock()`（`PARTIAL_WAKE_LOCK`），这正是 `WAKE_LOCK` 权限的用途，也是熄屏后
还能持续出声的机制。

还有一条**推翻常见假设**的：`audio_service` 只管「投影」，`audio_session` 只管「会话」，
两边都**不**保证自定义通知图标的存活方式相同。实测（release 包 + `resources.arsc`）：
插件自带的七个 `audio_service_play_arrow|pause|stop|...` **不会**被 `shrinkResources` 剥掉
（插件 README 原话「By default plugin's default icons are not stripped by R8」），
但**我们自己的** `drawable/ic_stat_slive` 只以字符串形式存在于 Dart 侧（进 `libapp.so`，
不进 dex），AAPT 看不到这条引用边，所以必须靠 `res/raw/keep.xml` 钉住。两者不是同一回事。

## 语义决定（有意为之，不是漏实现）

- **没有「上一首/下一首」**：直播既没有可拖的时间轴，也没有「下一集」。audio_service
  也没有「置灰」的概念——发出去的键就是一个按得动却毫无反应的键。同理不发 seek/快进/快退。
- **通知里的「停止」= 暂停出声 + 撤掉通知与前台服务**，不是 `player.stop()`。
  后者会推 EOS → `completed` → 走进 `mediaEnd()` 那套「播放结束就重连/换线路」的自愈
  逻辑，把「停止」当成一次意外断流，立刻又把流拉起来。
- **不发布 `duration`，也就不画进度条**（v1）。一开始的做法是「录像才发 duration」，
  复核时否掉了：只要发了 duration，Android 与 iOS 都会画出**可拖**的进度条，而我们不推
  `updatePosition`，那条会永远冻在 `0:00 / mm:ss` —— 一个看得见却拖着没反应的控件比
  没有控件更糟。真要做进度，必须同时接上 `player.stream.position`。
- **通知任何时候划不掉**（`androidNotificationOngoing: true` 的直接后果：Java 侧
  `buildNotification()` 只看这一个配置位就 `builder.setOngoing(true)`，**不区分**播放/暂停，
  `AudioService.java:646-650`）。所以退出入口是同一处配上去的那颗**取消键**
  （`setShowCancelButton(true)` + `ACTION_STOP` 的 PendingIntent），它落到 `stop()`。
  `onNotificationDeleted` 在这个配置下走不到，代码仍保留覆写，是给「通知确实可划」的
  机型或以后改配置兜底。
- **从最近任务划掉 app → 停止播放并撤通知**（`onTaskRemoved` → `stop()`）。划掉任务是
  「我不用了」的明确手势；留着的话用户面对的是一个已经不存在的 app 在说话。
- **暂停期间仍持有音频焦点**：媒体 app 的惯例，免得别的 app 顺势起播，也免得锁屏上
  再按播放要重新抢（iOS 挂起久了甚至抢不回来）。只在摘除/停止时释放。
- **`duck` 型中断不暂停**：那只是导航播报这类「让出音量」的请求，为它暂停一路直播很怪。
- **拔耳机/断蓝牙暂停在两个平台都有效**：`becomingNoisyEventStream` 不是 Android 独有，
  iOS 从 `AVAudioSessionRouteChangeReason.oldDeviceUnavailable` 也会发（已核 0.2.4 源码）。
  中断结束后**不自动续播**（直播被电话打断后静默出声会吓人），用户按播放即可。
- **抢焦点只挂在「真的推出 playing=true」这条边沿上**，不挂在 `attach()` 上：`attach`
  跟着 mpv 的事件率跑（弱网时 buffering 一秒跳好几回），在那里激活会把
  `requestAudioFocus` 打成连发。同理 `refresh()` 要去重——注意**不能用
  `PlaybackState ==`** 去重，它的 `==` 含 `updateTime`，而构造时默认取 `DateTime.now()`，
  两次内容完全一样的状态永远不相等，所以自己按会变的字段组键。
- **与「进入后台自动暂停」互斥**：两个同时开时，切后台那一刻就被暂停，「后台播放」名存
  实亡。互斥由 `AppSettingsController` 的两个 setter 强制（互相顶掉并各自落盘），
  UI 用 `SettingsSwitch` 的 `locked` + `lockedHint` 把被顶掉的那一项锁上并说明原因。
- **开关刚打开、但此刻没在播 → 通知还不出现**。这是 audio_service 的设计：只有
  `playing: true` 才拉起前台服务并画通知。

## 已知限制

1. **多开时通知只代表页面主格那一路**，四路继续各自出声。要让通知跟着聚焦格走，需要在
   聚焦切换处 attach/detach，属二期。
2. **完全没有进度条**（v1 的取舍，不是漏做）：既不推 `updatePosition`，也不发 `duration`。
   录像（`isRecord`）想显示进度，必须两件一起接上：`player.stream.position` 按 1s 节流
   推位置，并且只在非直播时发 duration。
3. **封面可能拉不到**：`MediaItem.artUri` 由 audio_service 自己的 cache manager 下载，
   **不带**页面上那些 referer/UA 请求头。B站/抖音 CDN 有防盗链时通知退化成纯文字。
   必要时二期改成先落本地文件、再把 `Uri.file(...)` 交出去。
4. **iOS 未在本机验证**：开发机是 Windows，无法构建也无法跑。iOS 侧的全部改动就是
   `LiveAudioSession` 的类别与激活（`Info.plist` 早就就位、`AppDelegate.swift` 未改）。
   上 Mac 之前，iOS 视为未验证。
5. **Android 12+ 在后台起前台服务会抛** `ForegroundServiceStartNotAllowedException`，
   而 `AudioService.enterPlayingState()` 里那句 `startForegroundService` **没有** try/catch。
   现在有两道缓解：
   * handler 的闸：「从没进过播放态 + 此刻在后台」时先按未播发布，回前台后的下一次
     再补。管的是「点进房间立刻按 Home、流才刚连上」那种时序。
   * 通知里的播放键本身是 PendingIntent（用户在手势上触发），按 Android 的豁免表这一路
     通常被允许。
   **仍待真机确认的一条**：`androidStopForegroundOnPause: true` 意味着暂停时前台服务降级，
   之后从通知/锁屏按播放是一次「后台重启前台服务」。插件 README 明确点出这个组合会中招，
   并给出解法：把 `androidStopForegroundOnPause` 设成 `false`，让服务一直留在前台状态。
   **本轮没这么改，是有代价权衡的**：`exitPlayingState()` 只在 `androidStopForegroundOnPause`
   为真时才调 `exitForegroundState()`，而释放 `PARTIAL_WAKE_LOCK` 就在那里面——设成 false
   会让暂停后**一直持有部分唤醒锁**，熄屏放兜里就是持续耗电。
   真机若真的复现「暂停后从锁屏按播放 → app 挂掉」，就改成 `false`，并接受耗电；
   这是一次单变量 A/B，别和别的改动混在一轮。
   注意配套约束：`androidStopForegroundOnPause: false` 时 `androidNotificationOngoing`
   **必须**跟着改成 `false`（那个 assert），届时通知就变成可划掉，`onNotificationDeleted`
   也才真正可达。

6. **后台按「停止」有可能顺带把 Flutter 引擎回收掉**。链路是：发出 idle →
   Dart 侧 `AudioService._stop()` → Java `stopSelf()` → `AudioService.onDestroy()` →
   `listener.onDestroy()` → `AudioServicePlugin.disposeFlutterEngine()`。
   但那个方法开头就有一句守卫：`if (clientInterface.activity != null) return;`
   ——**Activity 还活着就不会销毁引擎**。而 `onDetachedFromActivity`（把 activity 置 null
   的那步）是在 Activity **销毁**时才走，不是普通的切后台。所以：
   * 常见的「切后台 → 通知里按停止」：Activity 只是 stopped，仍在 → 引擎存活 →
     app 回到前台还是原来那个直播间页面。符合预期。
   * 只有当系统已经把 Activity 回收、只留进程（长时间挂后台）时，这一次 stop 才会连带
     销毁引擎，表现为「停止后 app  effectively 退出，下次是冷启动」。
   这条只在「用户主动要求结束」时可能发生，所以我们判定为**可接受**，但它是本次设计里
   最需要真机过一遍的一条（尤其要看冷启动后是否黑屏）。

## 验收要点

Android（真机，最好 Android 13+ 与更早各一台）：

1. 开开关 → 弹通知权限；拒绝后仍能后台出声，只是没有通知栏入口。
2. 进直播间 → 通知出现（封面/标题/主播/播放暂停/停止）。
3. Home 键 → 声音继续、通知仍在。
4. **熄屏 10 分钟以上仍出声**（验 `PARTIAL_WAKE_LOCK` 与 Doze）。
5. 通知与锁屏上的暂停/播放；通知右上角那颗**取消键**（X）→ 停止 + 通知消失；
   **划掉最近任务 → 停止 + 通知消失**。注意通知本体是划不掉的（`ongoing`，见已知限制），
   所以别拿「划掉通知」当验收动作。
6. 返回键离开直播间 → 声音停、通知立刻消失。
7. 耳机/蓝牙媒体键 play/pause；**拔出耳机立即暂停**；来电 → 暂停。
8. **PiP 回归**：进出 `floating` 小窗、点通知回 app、进程被杀后从通知冷启动。
   （换 `MainActivity` 父类的唯一风险面。）
9. 设置互斥：开 A 时 B 被锁（锁图标 + 提示），开 B 会关掉 A 并落盘；重启后状态一致。
10. 开着「后台播放」切走再回来不中断（这条验的是 `pauseOnBackground` 那个派生值，
    不是设置项本身）。
11. 桌面三端：构建与运行不受影响，设置页看不到「后台播放」这一行，分隔线数量与改前一致。
12. **【Android 12+ 专项】暂停后从锁屏/通知按播放**，多轮（暂停 → 搁一会儿 → 按播放）。
    这条对应已知限制 5：只有它真的红了，才去把 `androidStopForegroundOnPause` 改成
    `false`（并连带把 `androidNotificationOngoing` 改成 `false`），作为**单变量对照**跑，
    别和别的改动混在一轮里。
13. **【引擎回收专项】挂后台足够久（系统可能已销毁 Activity）之后，从通知按停止**，
    再重新打开 app：确认不是黑屏、能正常进直播间。对应已知限制 6。

## 已确认不构成问题的几条（免得下一轮重新怀疑）

* **release 包会不会把通知的动作图标收缩掉**：不会。实测 `app-release.apk` 的
  `resources.arsc` 里七个 `audio_service_*` 全在（`aapt2 dump resources`），插件 README
  也写了默认不剥。我们的 `keep.xml` 只需要管 `ic_stat_slive`。
  ⚠️ 取证口径：`res/` 的文件名被 AGP 缩短成 `res/-5.xml`，按文件名 grep APK 必然查不到；
  `uses-permission` 的名字在 aapt2 输出的**下一行**，同行 grep 会漏。
* **`AudioService.init` 是否会把服务绑起来/起前台服务**：不会。它只做
  `ensureInitialized` + `_platform.configure(...)` + 挂四个监听。代价仅是在 Android 上
  提前建了一条名叫「直播播放」的通知渠道（所有用户可见，即使没开这个功能）。
  也因此**不能**把 init 按开关延迟到首次使用——那样用户在运行中打开开关就没有通知，
  必须重启 app。
* **`_bgSuppressed` 只在 `initPlaylist` 里复位会不会卡死**：不会。凡是能让播放跑起来的
  路径（首次进房、换房间、换清晰度）都必过 `getPlayUrl → initPlaylist`；而
  `getPlayUrl` 在 `playUrls` 为空时提前返回，此时既没有播放也没有通知需求。

`setMultiPlayDefaultTiles` 目前没有任何 UI 调用点（「默认路数」设置项的入口还没接上），
它与本次改动无关，记录在此以免被误认为是回归。
