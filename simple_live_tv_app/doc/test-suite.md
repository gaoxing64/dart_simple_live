# simple_live_tv_app 测试案例库（面向 AI 的文字版）

> 版本锚点：`simple_live_tv_app` v1.5.1+10501 · future 分支 `5ae375f1`（2026-10-14）
> 配套文档：[workflow-diagram.md](./workflow-diagram.md)｜[architecture.md](./architecture.md)｜[update-history.md](./update-history.md)｜[backlog.md](./backlog.md)｜上游依赖：[simple_live_core 知识库](../../simple_live_core/doc/test-suite.md)

## 0. 结论先行

TV 端**几乎没有测试**：`test/` 下只有 1 个 `flutter create` 默认模板文件，且断言与真实 App 不符（详见 §2）。本文件因此以「现状 + 最小可做清单 + 手工冒烟」为主，参考 core 的**离线优先**范式（core 知识库 §5）。

## 1. 怎么跑

```bash
cd simple_live_tv_app
fvm flutter test                              # 全部（当前只有默认模板文件）
fvm flutter test test/widget_test.dart        # 单文件
fvm flutter analyze                           # 静态分析（android/windows/build 已在 analysis_options 中排除）
```

- 工程用 FVM 管理 Flutter，`.fvmrc` 锁 `3.35.7`（注意与 `simple_live_app` 的 `3.47.6` 不同）。
- **可测性前提**：TV 端 UI 与设备强耦合（`ScreenUtilInit`、`KeyboardListener`、media_kit 原生后端），widget 测试需较多样板；**优先从纯函数/DTO 切入**（§4.1），与 core 的离线范式一致，成本最低。

## 2. 现有测试资产

| 文件 | 用例数 | 类型 | 说明 |
| --- | --- | --- | --- |
| `test/widget_test.dart` | 1 | widget | **flutter create 默认模板残留**：`pumpWidget(const MyApp())` 后断言 `find.text('0')`/`Icons.add` 计数器逻辑（`:14-28`），真实 `MyApp` 无此内容，**实际会失败/无意义**，应删除或重写 |

**平台目标目录（非测试资产，需一并说明）**：

| 目录 | 性质 | 说明 |
| --- | --- | --- |
| `android/` | 交付主目标 | Android TV（`AndroidManifest.xml:34` 声明 `LEANBACK_LAUNCHER`、banner）；内含两个 `MainActivity` 历史遗留（`java/com/bgylde/live/MainActivity.java` 与 `kotlin/com/xycz/simple_live_tv/MainActivity.kt`） |
| `windows/` | 桌面调试目标 | 完整 CMake/Win32 运行器；`.metadata:14-20` 未登记 windows，`analysis_options.yaml:11-13` 排除分析 |
| `build/**` | 生成物 | 已在 `analysis_options.yaml:11-13` 排除 |

> `flutter test` 只采集 `test/` 目录，上述平台目录不进测试集。

## 3. 覆盖矩阵

| 能力 | 现状 | 目标 |
| --- | --- | --- |
| 纯函数（Utils/分类逻辑） | ❌ 无 | ✅ 离线，最高性价比（§4.1） |
| 数据模型（Hive DTO） | ❌ 无 | ✅ 离线（§4.2） |
| 分页控制器（`BasePageController`） | ❌ 无 | ✅ 离线（§4.3，绑定 backlog P1-1） |
| 账号（`Account` DTO / `PlatformService` / `MigrationService`） | ❌ 无（2026-10-14 才随 `6da36e04` 落入，一行测试都没加） | ✅ 离线：Hive 往返 + 版本阈值分支可纯测（§4.2 证据） |
| 同步服务的 JSON 处理 | ❌ 无 | ⚠️ 需 Hive/依赖注入，中优先 |
| 焦点/按键映射 | ❌ 无 | ⚠️ widget 测试 + 手工冒烟（§5） |
| 播放器/取流/弹幕 | ❌ 无 | 交由 core 的联网冒烟 + 手工验证 |
| 联网冒烟 | ❌ 无 | 可选，勿进 PR 必跑集 |

## 4. 文字版测试案例库

约定：`[已有]` = 现有用例覆盖；`[待补]` = 建议新增（给实现要点）。用例描述已足够 AI 直接转写为 `test()`。

### 4.1 纯函数（离线，最高优先）

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-TV-U01 | `Utils.parseVersion('1.5.0')` | 每段 `padLeft(2,'0')` 后拼接 → `10500` | [待补] |
| TC-TV-U02 | `Utils.parseVersion('1.6.6')` | → `10606` | [待补] |
| TC-TV-U03 | `Utils.onlineToString` | `9999`→`"9999"`；`10000`→`"1.0万"`；`123456`→`"12.3万"` | [待补] |
| TC-TV-U04 | `Utils.isRegexFormat` | `"/abc/"`→true；`"abc"`→false；`"/a/"`→false（长度≤2）；`"/"`→false | [待补] |
| TC-TV-U05 | `Utils.removeRegexFormat("/abc/")` | → `"abc"` | [待补] |
| TC-TV-U06 | `Utils.parseTime` | 同一天→`HH:mm`；同年→`MM-dd HH:mm`；跨年→`yyyy-MM-dd HH:mm`；`null`→`""` | [待补] |
| TC-TV-U07 | `AppLiveCategory.showAll` | `children.length < 19` 为 true，`==19` 为 false | [待补] |
| TC-TV-U08 | `AppLiveCategory.take15` | 始终最多 15 项 | [待补] |

> 证据：`app/utils.dart:18-35,176-184,269-283`；`modules/category/category_controller.dart:32-61`。

### 4.2 数据模型 / 持久化（离线）

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-TV-D01 | `FollowUser` Hive adapter 往返 | `写→读` 字段（id/roomId/siteId/userName/face/addTime/liveStatus）一致 | [待补] |
| TC-TV-D02 | `History` Hive adapter 往返 | 同上（含 `updateTime`） | [待补] |
| TC-TV-D03 | `DBService.getHistores()` 排序 | 按 `updateTime` 倒序 | [待补] |
| TC-TV-D04 | `DBService.getFollowExist` | 未关注→false，关注后→true | [待补] |

> 证据：`models/db/follow_user.dart`、`models/db/history.dart`、`services/db_service.dart:24-59`（注意 box 名 `"TVHostiry"` 拼写，见 backlog P1-2）。
> 2026-10-14 起还有第三个 DTO：`models/db/account.dart`（`@HiveType(typeId: 3)`，`:5`）与生成物 `account.g.dart`（`read` `:19-25` 只还原 id/siteId/credential/createdAt/updatedAt 五个字段，`write` `:31-41`），读写入口是 `db_service.dart:20-26`；`fromJson` 会丢 `userName/avatar/uid`（`account.dart:49-57`，对应 backlog P1-5）。TV 包内没有 `build_runner`（`pubspec.yaml:59-63`），生成物不能本地重算，见 backlog P2-8。

### 4.3 分页控制器（离线，绑定 backlog P1-1）

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-TV-B01 | 首页 `getData` 返回非空 | `currentPage` 自增、`canLoadMore=true`、`list` 被替换 | [待补] |
| TC-TV-B02 | 首页返回空 | `canLoadMore=false`、`pageEmpty=true`、不抛异常 | [待补] |
| TC-TV-B03 | 非首页返回空 | `canLoadMore=false`，但**不**置 `pageEmpty` | [待补] |
| TC-TV-B04 | `getData` 抛异常且首页 | `pageError=true`（`handleError(showPageError:true)`） | [待补] |
| TC-TV-B05 | `refreshData()` | 重置 `currentPage=1` 且清空 `list` 后重载 | [待补] |
| TC-TV-B06 | 分页契约（回归 P1-1） | 断言现状：`canLoadMore` **只**由「本页是否非空」决定，不读 core 的 `hasMore` | [待补]（现状锁定；修 P1-1 后改为断言采信 `hasMore`） |

> 证据：`app/controller/base_controller.dart:59-124`。测试要点：写一个 `BasePageController` 的测试子类，`getData` 返回可控 `List`（无需网络/Getx 初始化之外的东西）。

### 4.4 同步服务（中等优先，需依赖注入）

| ID | 用例 | 预期 | 状态 |
| --- | --- | --- | --- |
| TC-TV-S01 | `/sync/follow?overlay=1` | 先清空再写入，返回 `{status:true}` | [待补] |
| TC-TV-S02 | `/sync/history` 冲突合并 | 本地 `updateTime` 更新者不被覆盖 | [待补] |
| TC-TV-S03 | `/sync/blocked_word` | trim 后写入屏蔽词集合 | [待补] |
| TC-TV-S04 | 异常请求体 | 返回 `{status:false, message:...}`，不抛到进程外 | [待补] |

> 证据：`services/sync_service.dart:199-312`。落地需把 `DBService`/`AppSettingsController` 换成可注入桩（当前为 `Get.find` 单例）。
> 2026-10-14 变更：账号端点由 `/sync/account/bilibili` 改名 `/sync/account/account`（`sync_service.dart:152`），handler `_syncAccountRequest` 在 `:294-312`，整包按 `Account.fromJson` 解析（`:299`）后只 `updateAccount`（`:300`）——与手机端发送地址 `simple_live_app/lib/requests/sync_client_request.dart:99` 一致。新增端点同样适用 TC-TV-S04 的「异常请求体 → `{status:false}`」断言（缺 `createdAt/updatedAt` 时 `fromJson` 直接抛，走 `:306-311` 的 catch），但**别**断言「同步后账号即变已登录」，那正是 backlog P1-5 的行为缺口。

## 5. 遥控器手工冒烟清单（可执行按键序列）

> 设备：Android TV / 模拟器（横屏）。每步给「按键序列 → 期望」。

1. **冷启动**：`启动` → 首次运行显示用户协议页 `/agreement`；`OK` 确认 → 进入首页 `/home`；界面为横屏全屏、无系统栏。
2. **首页焦点**：`→/←/↑/↓` 在「热门直播/直播类目/搜索直播/观看记录/数据同步/设置」间移动 → 焦点项放大(1.1)+白底黑字+阴影（`highlight_widget.dart:77-91`）。
3. **进入列表**：焦点到「热门直播」→ `OK` → 瀑布流卡片；`↓` 到底部 → 自动加载下一页（`hot_live_controller.dart:20-25`）。
4. **返回**：`返回` → 回首页；再 `返回` → 仍在首页（无栈可退时不应崩溃）。
5. **搜索**：首页「搜索直播」→ `OK`；`←/→` 在「直播间/主播」切换（`selected` 高亮）；输入关键字 → `OK(search)` → 结果列表；`OK` 进房间。
6. **类目**：首页「直播类目」→ `OK`；`←/→` 切平台（bilibili/douyu/huya/douyin，`category_page.dart:75-93`）；`OK` 选子类 → 类目详情列表。
7. **房间播放**：`OK` 唤出/隐藏控制条（底部显示清晰度/线路/弹幕/分辨率，`player_controls.dart:131-211`）；`Menu(或 →)` 打开播放设置；在设置内 `←/→` 循环改「清晰度/线路/画面比例/弹幕开关」并即时生效；`返回` 关闭设置并**还原焦点**（`player_controls.dart:594-597`）。
8. **切台**：房间内 `↑` 上一频道 / `↓` 下一频道（仅关注中在播的频道，无则 Toast「没有正在直播的频道」，`live_room_controller.dart:376-420`）。
9. **关注弹窗**：房间内 `←` 打开「我的关注」→ 选中主播 `OK` 切换房间（`changePlayLine`/`resetRoom`）。
10. **退出房间**：`返回` 一次 → Toast「再按一次退出播放器」；2 秒内再 `返回` → 退出（`live_room_page.dart:19-36`）。
11. **未开播/录像**：进未开播房间 → 显示「未开播」（`live_room_page.dart:144-155`）；录像房间 → Toast「当前主播未开播，正在轮播录像」（`live_room_controller.dart:156-158`）。
12. **断网**：拔网进列表/房间 → 列表页显示错误态并可刷新（`page_grid_view.dart:55-61`）；房间页 Toast 错误不崩溃。
13. **同步**：首页「数据同步」→ 显示本机二维码（`sync_page.dart:63-79`）；手机推送关注 → 首页关注区刷新（`EventBus` `kUpdateFollow`）。
14. **扫码登录**：设置 → 账号 Tab → `OK` 选中「哔哩哔哩」或「斗鱼直播」项（`settings_page.dart:429-445`）→ 跳 `/qr_login/qr_login`，AppBar 标题「〈站点名〉账号登录」（`qr_login_page.dart:16`）、中央二维码（`:55-61`）；手机扫码确认后由 3 秒轮询命中 → 自动 `Get.back()` 回设置页（`qr_login_controller.dart:63-66`），该项副标题从「暂未登录」变昵称（`settings_page.dart:436`）；二维码加载失败时显示「二维码加载失败」+ 重试（`qr_login_page.dart:27-37`）；凭证失效 → Toast「〈站点名〉账号失效，请重新设置」（`platform_service.dart:56-58`）。
15. **账号同步后的显示**：手机端推账号 → TV Toast「已同步〈siteId〉账号」（`sync_service.dart:301`）；此时设置页**仍显示「暂未登录」**，要退出重开走一遍 `initAccount()` 才刷新（`platform_service.dart:15-21`）——这是 backlog P1-5 记录的既有行为，冒烟时按「已知缺陷」验收，勿当崩溃。

> 虎牙/抖音两项在 TV 设置页是硬编码「无需登录」（`settings_page.dart:452-478`），点按只出 Toast，不进扫码页；core 侧这两个站点未实现扫码（`huya_site.dart:567-582`、`douyin_site.dart:1290-1299` 抛 `UnimplementedError`）。

## 6. 写新测试的约定

1. **离线优先**：能靠纯函数/构造数据覆盖的，一律不写联网用例（对齐 core 约定）。
2. **优先切面**：`Utils`、`AppLiveCategory` 逻辑、Hive DTO、`BasePageController` —— 均无需原生后端。
3. **避免 flaky**：不要断言墙钟耗时/播放器真实帧；UI 只断言结构与状态（`isFoucsed`、可见性）。
4. **命名**：文件 `<域>_<主题>_test.dart`；用例名用中文描述行为 + 括号给关键条件；`reason:` 写清「为什么该断言值得守护」。
5. **契约变更时**：先改测试期望值，并在说明里引用本文件 ID（如「TC-TV-B06 由现状切到采信 hasMore」）。
6. **恒等测试**：`test/widget_test.dart` 提交前建议删除或替换为「首页可渲染」的最小冒烟，避免 CI 假红。

## 7. 与 backlog 的对应

- §4.3 的 TC-TV-B06 对应 backlog **P1-1**（分页未采信 core `hasMore`）；修完后同一用例即成为回归护栏。
- §4.1/§4.2 是 backlog **P2-5**（测试资产为空）的最小可做清单起点。
- §5 的手工冒烟覆盖 backlog **P0-1**（焦点节点丢失）与 P1-4 的播放兼容性验证路径。
- §4.4 的 TC-TV-S01~S04 依赖同步服务可注入化，与 backlog **P2-1**（僵尸设置/依赖裁剪）同批推进更省力。
- §5 第 14~15 步对应 backlog **P1-5**（同步来的账号不即时生效）与 **P1-7**（`siteId` 解包崩溃）；账号链路的离线用例暂未编 TC 号，补测时先覆盖两条：`Account` 适配器只落 5 个字段（`models/db/account.g.dart:19-25,31-41`）、`MigrationService` 的版本阈值分支（`services/migration_service.dart:12-14,19-40`，纯 LocalStorage + DBService 桩）。