library;

export 'src/interface/live_site.dart';
export 'src/interface/live_danmaku.dart';
export 'src/bridge/rust_bilibili_site.dart';
export 'src/bridge/rust_douyu_site.dart';
export 'src/bridge/rust_huya_site.dart';
export 'src/bridge/rust_douyin_site.dart';
export 'src/bridge/rust_twitch_site.dart';
// FRB 生成物公共面：RustLib（init）、DanmakuMask
// 注意：不导出 api/slive/error.dart —— 其 CoreError 与 Dart core
// common/core_error.dart 的 CoreError 同名，双导出会在同时引用两处的
// 平台文件里造成歧义（douyin_site.dart 实测）；消费方按需深导入。
export 'src/rust/frb_generated.dart';
export 'src/rust/api/danmaku_mask.dart';
export 'src/platforms/huya/huya_site.dart';
export 'src/platforms/bilibili/bilibili_site.dart';
export 'src/platforms/douyu/douyu_site.dart';
export 'src/platforms/douyin/douyin_site.dart';
export 'src/common/core_log.dart';
export 'src/common/qr_status.dart';
export 'src/model/live_message.dart';
export 'src/platforms/bilibili/bilibili_danmaku.dart';
export 'src/platforms/douyu/douyu_danmaku.dart';
export 'src/platforms/huya/huya_danmaku.dart';
export 'src/platforms/douyin/douyin_danmaku.dart';

export 'src/model/live_category_result.dart';
export 'src/model/live_category.dart';
export 'src/model/live_play_quality.dart';
export 'src/model/live_room_detail.dart';
export 'src/model/live_room_item.dart';
export 'src/model/live_search_result.dart';
export 'src/model/live_anchor_item.dart';
export 'src/model/live_play_url.dart';
export 'src/model/account_info.dart';
export 'src/model/account_qr_code.dart';
