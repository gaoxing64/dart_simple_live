library;

export 'src/interface/live_site.dart';
export 'src/interface/live_danmaku.dart';
export 'src/bridge/rust_bilibili_site.dart';
export 'src/bridge/rust_douyu_site.dart';
export 'src/bridge/rust_huya_site.dart';
export 'src/bridge/rust_douyin_site.dart';
export 'src/bridge/rust_twitch_site.dart';
// FRB 生成物公共面：RustLib（init）、DanmakuMask
// 注意：不导出 api/slive/error.dart —— 桥层只在内部映射 CoreError，
// 消费方若需判类型按需深导入，避免与业务异常混在同一命名空间。
export 'src/rust/frb_generated.dart';
export 'src/rust/api/danmaku_mask.dart';
export 'src/common/core_log.dart';
export 'src/common/qr_status.dart';
export 'src/model/live_message.dart';

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
