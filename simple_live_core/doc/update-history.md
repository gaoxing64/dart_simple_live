# simple_live_core 修改历史(Git 复现)

> 本文件由 gen_update_history.py 根据 Git 历史自动生成,请勿手工修改正文;内容变化时重新生成即可。
> 
> 组件路径: `simple_live_core`
> 提交总数: 50 · 时间跨度: 2026-07-30 ~ 2026-10-18 · 代码净增: +114358 −4274
> 主要贡献者: SlotSun(31), gaoxing64(19)

## 2026-07-30

### `543910ba` feat(follow): add follow_user.last_watch_time · @SlotSun
- `simple_live_core/.fvmrc` +3 −0
- `simple_live_core/.gitattributes` +1 −0
- `simple_live_core/.gitignore` +14 −0
- `simple_live_core/.vscode/launch.json` +14 −0
- `simple_live_core/CHANGELOG.md` +3 −0
- `simple_live_core/README.md` +3 −0
- `simple_live_core/analysis_options.yaml` +30 −0
- `simple_live_core/assets/js/crypto-js-md5.min.js` +30 −0
- `simple_live_core/assets/js/douyin-webmssdk.js` +7035 −0
- `simple_live_core/example/simple_live_core_example.dart` +38 −0
- `simple_live_core/lib/simple_live_core.dart` +24 −0
- `simple_live_core/lib/src/common/binary_writer.dart` +149 −0
- `simple_live_core/lib/src/common/convert_helper.dart` +6 −0
- `simple_live_core/lib/src/common/core_error.dart` +41 −0
- `simple_live_core/lib/src/common/core_log.dart` +88 −0
- …(其余 71 个文件省略)

## 2026-08-04

### `9875d820` fix: 虎牙弹幕缺失问题 #164 #84 · @SlotSun
- `simple_live_core/lib/src/platforms/huya/huya_danmaku.dart` +20 −9
- `simple_live_core/lib/src/platforms/huya/huya_site.dart` +2 −2

## 2026-08-17

### `72e00adb` feat(core): support huya super chat (test) · @SlotSun
- `simple_live_core/lib/src/model/tars/game_event_message_board_info.dart` +62 −0
- `simple_live_core/lib/src/model/tars/game_event_message_board_panel.dart` +38 −0
- `simple_live_core/lib/src/model/tars/get_game_event_message_board_req.dart` +52 −0
- `simple_live_core/lib/src/model/tars/get_game_event_message_board_rsp.dart` +35 −0
- `simple_live_core/lib/src/model/tars/types.dart` +31 −0
- `simple_live_core/lib/src/platforms/huya/huya_danmaku.dart` +20 −3
- `simple_live_core/lib/src/platforms/huya/huya_request_params.dart` +28 −0
- `simple_live_core/lib/src/platforms/huya/huya_site.dart` +14 −9
- `simple_live_core/lib/src/platforms/huya/huya_utils.dart` +79 −4

### `7453d626` fix: huya super chat logic · @SlotSun
- `simple_live_core/lib/src/platforms/huya/huya_utils.dart` +2 −0

## 2026-08-23

### `e665a7b7` refactor(core): huya弹幕数据模型业务逻辑更符合流程 · @SlotSun
- `simple_live_core/analysis_options.yaml` +9 −0
- `simple_live_core/lib/src/model/tars/huya_danmaku.dart` +0 −122
- `simple_live_core/lib/src/platforms/huya/huya_danmaku.dart` +138 −48
- `simple_live_core/lib/src/platforms/huya/huya_site.dart` +3 −3
- `simple_live_core/lib/src/platforms/huya/huya_utils.dart` +16 −3
- `simple_live_core/lib/src/platforms/huya/model/huya_damaku_model.dart` +197 −0
- `simple_live_core/lib/src/{model => platforms/huya}/tars/game_event_message_board_info.dart` +1 −1
- `simple_live_core/lib/src/{model => platforms/huya}/tars/game_event_message_board_panel.dart` +0 −0
- `simple_live_core/lib/src/{model => platforms/huya}/tars/get_cdn_token_ex_req.dart` +1 −1
- `simple_live_core/lib/src/{model => platforms/huya}/tars/get_cdn_token_ex_resp.dart` +0 −0
- `simple_live_core/lib/src/{model => platforms/huya}/tars/get_game_event_message_board_req.dart` +1 −1
- `simple_live_core/lib/src/{model => platforms/huya}/tars/get_game_event_message_board_rsp.dart` +0 −0
- `simple_live_core/lib/src/platforms/huya/tars/huya_danmaku.dart` +414 −0
- `simple_live_core/lib/src/{model => platforms/huya}/tars/tar2dart.dart` +0 −0
- `simple_live_core/lib/src/{model => platforms/huya}/tars/types.dart` +0 −0
- …(其余 3 个文件省略)

## 2026-09-01

### `0c4fbf83` fix(core): increase huya-sc fetch limit from 10 to 50 · @SlotSun
- `simple_live_core/lib/src/platforms/huya/huya_utils.dart` +6 −5

## 2026-09-04

### `4db38b22` chore: 逐步实现huya-js 流程完整化 · @SlotSun
- `simple_live_core/lib/src/platforms/huya/huya_danmaku.dart` +43 −38
- `simple_live_core/lib/src/platforms/huya/huya_utils.dart` +48 −1
- `simple_live_core/lib/src/platforms/huya/tars/enter_channel_req.dart` +47 −0

## 2026-09-10

### `fae186bf` refactor(block): 构造follow_user_block的model 和 crud · @SlotSun
- `simple_live_core/lib/src/model/live_message.dart` +4 −0

## 2026-09-11

### `e1f7a75c` feat(list): 分页采信服务端 hasMore，收敛为单一触发路径并补齐失败重试入口 · @gaoxing64
- `simple_live_core/CHANGELOG.md` +11 −0
- `simple_live_core/lib/src/interface/live_site.dart` +8 −2
- `simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart` +6 −3
- `simple_live_core/lib/src/platforms/douyin/douyin_site.dart` +24 −9
- `simple_live_core/lib/src/platforms/douyu/douyu_site.dart` +23 −4
- `simple_live_core/lib/src/platforms/huya/huya_site.dart` +5 −2
- `simple_live_core/lib/src/platforms/twitch/twitch_site.dart` +2 −2
- `simple_live_core/pubspec.yaml` +1 −1
- `simple_live_core/test/douyu_recommend_paging_test.dart` +127 −0

### `49eef9c3` feat(douyin): 抖音推荐流恢复真分页，列表到底给出明确提示 · @gaoxing64
- `simple_live_core/lib/src/model/live_category_result.dart` +1 −0
- `simple_live_core/lib/src/platforms/douyin/douyin_site.dart` +291 −60
- `simple_live_core/test/douyin_category_paging_test.dart` +267 −0
- `simple_live_core/test/douyin_recommend_fanout_test.dart` +440 −0

### `a5e594dc` feat(danmaku): 弹幕与聊天区支持 B 站表情包，OSD 统计面板收敛为单页 · @gaoxing64
- `simple_live_core/lib/src/model/live_message.dart` +52 −0
- `simple_live_core/lib/src/platforms/bilibili/bilibili_danmaku.dart` +7 −4
- `simple_live_core/lib/src/platforms/bilibili/bilibili_emoticon.dart` +193 −0
- `simple_live_core/test/bilibili_emoticon_test.dart` +264 −0

## 2026-09-12

### `48aedc9a` fix: 修正分页、表情与桌面交互的遗留问题 · @gaoxing64
- `simple_live_core/lib/src/platforms/bilibili/bilibili_emoticon.dart` +22 −4
- `simple_live_core/lib/src/platforms/douyin/douyin_site.dart` +86 −34
- `simple_live_core/test/bilibili_emoticon_test.dart` +73 −4
- `simple_live_core/test/douyin_category_paging_test.dart` +23 −0
- `simple_live_core/test/douyin_recommend_fanout_test.dart` +76 −1

## 2026-09-14

### `cb7f9919` chore(core): sync huya-ua · @SlotSun
- `simple_live_core/lib/src/platforms/huya/huya_request_params.dart` +1 −1

## 2026-09-16

### `63c1eb8d` fix: 修复分页、播放器与桌面交互的遗留问题 · @gaoxing64
- `simple_live_core/lib/src/platforms/douyin/douyin_site.dart` +294 −78
- `simple_live_core/test/douyin_linkmic_room_test.dart` +332 −0

## 2026-09-22

### `b492f965` fix(douyu): douyu 游客模式直播流只能存活5min,需要配置 cookie · @SlotSun
- `simple_live_core/lib/src/interface/live_site.dart` +5 −0
- `simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart` +5 −0
- `simple_live_core/lib/src/platforms/douyin/douyin_site.dart` +27 −3
- `simple_live_core/lib/src/platforms/douyu/douyu_site.dart` +18 −23
- `simple_live_core/lib/src/platforms/douyu/douyu_utils.dart` +45 −18
- `simple_live_core/lib/src/platforms/huya/huya_site.dart` +7 −0
- `simple_live_core/lib/src/platforms/twitch/twitch_site.dart` +6 −0

### `9199926c` refactor: 优化部分代码逻辑 · @SlotSun
- `simple_live_core/lib/src/platforms/douyin/douyin_danmaku.dart` +1 −4
- `simple_live_core/lib/src/platforms/douyin/douyin_site.dart` +40 −95
- `simple_live_core/lib/src/platforms/douyin/douyin_utils.dart` +1 −0
- `simple_live_core/lib/src/platforms/huya/huya_request_params.dart` +2 −4
- `simple_live_core/lib/src/platforms/huya/huya_site.dart` +6 −16

## 2026-09-23

### `4714974c` fix(douyu): 海外用户可以免登录看蓝光4m不断 temp · @SlotSun
- `simple_live_core/lib/src/platforms/douyu/douyu_site.dart` +6 −0
- `simple_live_core/lib/src/platforms/douyu/douyu_utils.dart` +1 −1

## 2026-09-24

### `2a0f4568` fix(douyin): 补上 LiveSite.setSiteAttrs 接口实现 · @gaoxing64
- `simple_live_core/lib/src/platforms/douyin/douyin_site.dart` +15 −0

### `249ff1b9` fix(douyu): 额外配置实现cookie不过期 · @SlotSun
- `simple_live_core/lib/src/common/http_client.dart` +33 −0
- `simple_live_core/lib/src/common/parse_cookie.dart` +30 −0
- `simple_live_core/lib/src/platforms/douyu/douyu_site.dart` +10 −0
- `simple_live_core/lib/src/platforms/douyu/douyu_utils.dart` +61 −2

## 2026-09-29

### `aed42c1e` feat(danmaku): 弹幕与聊天区支持 B 站表情包 · @gaoxing64
- `simple_live_core/lib/src/model/live_message.dart` +52 −0
- `simple_live_core/lib/src/platforms/bilibili/bilibili_danmaku.dart` +7 −4
- `simple_live_core/lib/src/platforms/bilibili/bilibili_emoticon.dart` +211 −0
- `simple_live_core/test/bilibili_emoticon_test.dart` +333 −0

## 2026-09-30

### `3d237b0e` fix(core): 表情包解析对齐 B 站真实载荷并区分大小表情 · @gaoxing64
- `simple_live_core/lib/src/model/live_message.dart` +18 −0
- `simple_live_core/lib/src/platforms/bilibili/bilibili_danmaku.dart` +4 −2
- `simple_live_core/lib/src/platforms/bilibili/bilibili_emoticon.dart` +123 −30
- `simple_live_core/test/bilibili_emoticon_test.dart` +224 −7

### `146c4a2c` chore(huya): 通过正则拉起huya-sc · @SlotSun
- `simple_live_core/lib/src/platforms/huya/huya_danmaku.dart` +22 −13
- `simple_live_core/lib/src/platforms/huya/huya_utils.dart` +4 −1

## 2026-10-01

### `8c9fc881` feat: support huya emoticon · @SlotSun
- `simple_live_core/lib/src/platforms/huya/huya_danmaku.dart` +17 −16
- `simple_live_core/lib/src/platforms/huya/huya_emoticon.dart` +123 −0

## 2026-10-03

### `062d5a83` refactor: 调整项目结构 · @SlotSun
- `simple_live_core/example/simple_live_core_example.dart` +2 −2
- `simple_live_core/lib/src/interface/live_site.dart` +2 −2
- `simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart` +2 −2
- `simple_live_core/lib/src/platforms/douyin/douyin_site.dart` +2 −2
- `simple_live_core/lib/src/platforms/douyu/douyu_site.dart` +2 −2
- `simple_live_core/lib/src/platforms/huya/{ => common}/huya_request_params.dart` +0 −0
- `simple_live_core/lib/src/platforms/huya/common/huya_vip_room_id.dart` +82 −0
- `simple_live_core/lib/src/platforms/twitch/twitch_site.dart` +2 −2
- `simple_live_core/test/simple_live_core_test.dart` +2 −2

### `aed6a865` feat: 跳过 huya vip 清晰度 #187 · @SlotSun
- `simple_live_core/lib/src/platforms/huya/huya_site.dart` +12 −5
- `simple_live_core/lib/src/platforms/huya/huya_utils.dart` +8 −1

### `b1df5968` fix: SC时间戳对不齐，改由价格&用户名&消息判断去重 · @SlotSun
- `simple_live_core/lib/src/platforms/douyu/douyu_site.dart` +1 −0
- `simple_live_core/lib/src/platforms/douyu/douyu_utils.dart` +7 −1

### `88ee03b5` fix: 完善斗鱼cookie管理，提示用户续期cookie · @SlotSun
- `simple_live_core/lib/src/platforms/douyu/douyu_utils.dart` +3 −1

### `d02d2e49` fix(huya): 偶尔因个别线路请求失败导致的断流 · @SlotSun
- `simple_live_core/lib/src/platforms/huya/common/huya_request_params.dart` +29 −0
- `simple_live_core/lib/src/platforms/huya/huya_danmaku.dart` +0 −1
- `simple_live_core/lib/src/platforms/huya/huya_site.dart` +8 −3

## 2026-10-10

### `e3a090ad` refactor(account): 逐步迁移账号登录从app到core，项目架构更清晰 · @SlotSun
- `simple_live_core/lib/src/common/common_asT.dart` +6 −0
- `simple_live_core/lib/src/common/qr_status.dart` +7 −0
- `simple_live_core/lib/src/interface/live_site.dart` +22 −1
- `simple_live_core/lib/src/model/account_info.dart` +70 −0
- `simple_live_core/lib/src/model/account_qr_code.dart` +74 −0

### `3a4ddb70` refactor(account): 实现 bilibili_account 接口 · @SlotSun
- `simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart` +92 −24
- `simple_live_core/lib/src/platforms/bilibili/model/bilibili_user_info.dart` +56 −0
- `simple_live_core/lib/src/platforms/douyin/douyin_site.dart` +26 −5
- `simple_live_core/lib/src/platforms/huya/huya_site.dart` +24 −3
- `simple_live_core/lib/src/platforms/twitch/twitch_site.dart` +21 −1

### `b5967198` refactor(account): 实现 douyu_account 接口 · @SlotSun
- `simple_live_core/lib/src/platforms/douyu/douyu_site.dart` +95 −3
- `simple_live_core/lib/src/platforms/douyu/douyu_utils.dart` +34 −1

### `e88268c6` refactor(account): 完成account 站点分流基础功能 · @SlotSun
- `simple_live_core/lib/simple_live_core.dart` +3 −0
- `simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart` +11 −14

## 2026-10-11

### `b3451ace` fix(account): credential 数据拼装 · @SlotSun
- `simple_live_core/lib/src/model/account_info.dart` +3 −0
- `simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart` +10 −7

### `e3f67344` refactor(account): 跑通QRcode全流程 · @SlotSun
- `simple_live_core/lib/src/platforms/douyu/douyu_site.dart` +31 −11
- `simple_live_core/lib/src/platforms/douyu/douyu_utils.dart` +7 −9

### `63a3055c` style: dart format . · @SlotSun
- `simple_live_core/analysis_options.yaml` +3 −0
- `simple_live_core/lib/src/platforms/bilibili/bilibili_danmaku.dart` +5 −11
- `simple_live_core/lib/src/platforms/bilibili/bilibili_emoticon.dart` +3 −7
- `simple_live_core/lib/src/platforms/douyin/abogus.dart` +15 −32
- `simple_live_core/lib/src/platforms/douyin/douyin_danmaku.dart` +3 −6
- `simple_live_core/lib/src/platforms/douyin/douyin_utils.dart` +1 −2
- `simple_live_core/lib/src/platforms/douyin/proto/douyin.pb.dart` +466 −912
- `simple_live_core/lib/src/platforms/douyin/proto/douyin.pbenum.dart` +4 −8
- `simple_live_core/lib/src/platforms/douyin/proto/douyin.pbjson.dart` +466 −1253
- `simple_live_core/lib/src/platforms/douyin/xbogus.dart` +12 −19
- `simple_live_core/lib/src/platforms/douyu/douyu_danmaku.dart` +5 −10
- `simple_live_core/lib/src/platforms/douyu/douyu_utils.dart` +7 −6
- `simple_live_core/lib/src/platforms/huya/common/huya_vip_room_id.dart` +1 −1
- `simple_live_core/lib/src/platforms/huya/huya_emoticon.dart` +1 −1
- `simple_live_core/lib/src/platforms/huya/huya_site.dart` +27 −66
- …(其余 11 个文件省略)

### `aa5f8073` refactor(account): 完成平台账号数据同步迁移工作 · @SlotSun
- `simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart` +21 −48
- `simple_live_core/lib/src/platforms/bilibili/model/bilibili_user_info.dart` +21 −21
- `simple_live_core/lib/src/platforms/douyin/douyin_site.dart` +40 −34
- `simple_live_core/lib/src/platforms/douyin/model/douyin_user_info.dart` +48 −0
- `simple_live_core/lib/src/platforms/douyu/douyu_site.dart` +22 −47

## 2026-10-12

### `57d8f86d` fix(bili): 迁移到Account cookie 不生效 #https://github.com/SlotSun/dart_simple_live/issues/197#issuecomment-6118992744 · @SlotSun
- `simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart` +4 −1

### `03c4493a` fix(bili): 补充弹幕 cookie 需要配对的uid · @SlotSun
- `simple_live_core/lib/src/platforms/bilibili/bilibili_site.dart` +1 −0

## 2026-10-14

### `64d2c634` docs(core): 新增 simple_live_core 知识库（5 份，锚点 abca65f8） · @gaoxing64
- `simple_live_core/doc/architecture.md` +165 −0
- `simple_live_core/doc/backlog.md` +169 −0
- `simple_live_core/doc/test-suite.md` +177 −0
- `simple_live_core/doc/update-history.md` +251 −0
- `simple_live_core/doc/workflow-diagram.md` +330 −0

## 2026-10-16

### `77eebd63` fix(douyu): 新增本地续流中转，修复未配置 cookie 时约 5 分钟断流 · @gaoxing64
- `simple_live_core/lib/src/model/live_play_url.dart` +18 −1
- `simple_live_core/lib/src/platforms/douyu/douyu_site.dart` +30 −7
- `simple_live_core/test/douyu_play_url_renew_test.dart` +149 −0

### `4dcdb4fe` docs(douyu): 续流中转落地后同步 core/app 文档 · @gaoxing64
- `simple_live_core/doc/architecture.md` +1 −1
- `simple_live_core/doc/backlog.md` +4 −1
- `simple_live_core/doc/test-suite.md` +3 −0
- `simple_live_core/doc/workflow-diagram.md` +7 −3

## 2026-10-17

### `97413c60` fix(core): listen real uri to get list of huya-sc #157 · @SlotSun
- `simple_live_core/lib/src/platforms/huya/huya_danmaku.dart` +13 −39

### `70c1c717` refactor: Rust workspace 迁至 simple_live_core（ADR-001 预留路径落地） · @gaoxing64
- `simple_live_core/.gitignore` +3 −0
- `simple_live_core/Cargo.lock` +2482 −0
- `simple_live_core/Cargo.toml` +34 −0
- `simple_live_core/README.md` +30 −0
- `simple_live_core/crates/slive-core/Cargo.toml` +58 −0
- `simple_live_core/crates/slive-core/src/error.rs` +158 −0
- `simple_live_core/crates/slive-core/src/http.rs` +206 −0
- `simple_live_core/crates/slive-core/src/lib.rs` +24 −0
- `simple_live_core/crates/slive-core/src/logging.rs` +49 −0
- `simple_live_core/crates/slive-core/src/models/account.rs` +55 −0
- `simple_live_core/crates/slive-core/src/models/category.rs` +25 −0
- `simple_live_core/crates/slive-core/src/models/danmu.rs` +23 −0
- `simple_live_core/crates/slive-core/src/models/message.rs` +142 −0
- `simple_live_core/crates/slive-core/src/models/mod.rs` +23 −0
- `simple_live_core/crates/slive-core/src/models/play.rs` +25 −0
- …(其余 327 个文件省略)

### `a02829f1` fix(tests): 虎牙夹具 key 改名 —— 消除误触 GitHub Secret Scanning 的 live_ 前缀模式 · @gaoxing64
- `simple_live_core/crates/slive-core/tests/ac_huya_golden.rs` +1 −1
- `simple_live_core/crates/slive-core/tests/ac_huya_http.rs` +2 −2
- `simple_live_core/crates/slive-core/tests/fixtures/huya/http/http-samples.json` +1 −1

### `73e80b1e` refactor(core): FRB 资产与 Dart 绑定层迁入 simple_live_core，App 直连 Rust 去开关 · @gaoxing64
- `simple_live_core/analysis_options.yaml` +8 −0
- `simple_live_core/flutter_rust_bridge.yaml` +3 −0
- `simple_live_core/lib/simple_live_core.dart` +11 −1
- `simple_live_core/lib/src/bridge/rust_bilibili_site.dart` +199 −0
- `simple_live_core/lib/src/bridge/rust_douyin_models.dart` +160 −0
- `simple_live_core/lib/src/bridge/rust_douyin_site.dart` +242 −0
- `simple_live_core/lib/src/bridge/rust_douyu_models.dart` +212 −0
- `simple_live_core/lib/src/bridge/rust_douyu_site.dart` +192 −0
- `simple_live_core/lib/src/bridge/rust_huya_models.dart` +31 −0
- `simple_live_core/lib/src/bridge/rust_huya_site.dart` +202 −0
- `simple_live_core/lib/src/bridge/rust_site_models.dart` +209 −0
- `simple_live_core/lib/src/bridge/rust_twitch_site.dart` +226 −0
- `simple_live_core/lib/src/rust/api/danmaku_mask.dart` +36 −0
- `simple_live_core/lib/src/rust/api/simple.dart` +10 −0
- `simple_live_core/lib/src/rust/api/slive/danmaku.dart` +32 −0
- …(其余 69 个文件省略)

### `e0cd41a6` refactor(core): 删除 Dart Twitch 平台实现（消费者归零） · @gaoxing64
- `simple_live_core/lib/src/platforms/twitch/twitch_danmaku.dart` +0 −104
- `simple_live_core/lib/src/platforms/twitch/twitch_models.dart` +0 −264
- `simple_live_core/lib/src/platforms/twitch/twitch_site.dart` +0 −320

### `6dd27ec6` docs: ADR-014 全面采用 Rust core，同步结构与路径文档 · @gaoxing64
- `simple_live_core/README.md` +21 −8

### `30bf6aae` feat(core): 抖音弹幕支持会员表情与标准表情 · @gaoxing64
- `simple_live_core/crates/slive-core/src/models/message.rs` +1 −1
- `simple_live_core/crates/slive-core/src/platforms/douyin/danmaku/decode.rs` +258 −7
- `simple_live_core/crates/slive-core/src/platforms/douyin/danmaku/emoticon.rs` +305 −0
- `simple_live_core/crates/slive-core/src/platforms/douyin/danmaku/mod.rs` +1 −0
- `simple_live_core/crates/slive-core/src/platforms/douyin/danmaku/proto.rs` +93 −3
- `simple_live_core/crates/slive-core/tests/ac_douyin_danmaku.rs` +75 −3
- `simple_live_core/doc/architecture.md` +3 −2
- `simple_live_core/doc/backlog.md` +2 −2
- `simple_live_core/doc/test-suite.md` +9 −3

## 2026-10-18

### `2c0cf372` fix(core): 修复虎牙 SC 拉取嵌套 runtime 导致弹幕静默停更 · @gaoxing64
- `simple_live_core/crates/slive-core/src/platforms/huya/danmaku/mod.rs` +13 −3
- `simple_live_core/crates/slive-core/src/platforms/huya/danmaku/super_chat_map.rs` +2 −2
- `simple_live_core/crates/slive-core/tests/ac_huya_danmaku.rs` +66 −4
- `simple_live_core/lib/src/bridge/rust_huya_site.dart` +11 −0
- `simple_live_core/src/api/slive/huya.rs` +7 −11

### `4795b165` docs: 同步斗鱼续流「上下文驱动」契约与测试口径 · @gaoxing64
- `simple_live_core/doc/architecture.md` +2 −1
- `simple_live_core/doc/backlog.md` +1 −1
- `simple_live_core/doc/test-suite.md` +1 −1
- `simple_live_core/doc/workflow-diagram.md` +7 −4

---

_重新生成命令:_

```bash
python gen_update_history.py simple_live_core
```

<!-- generated-by: gen_update_history.py -->