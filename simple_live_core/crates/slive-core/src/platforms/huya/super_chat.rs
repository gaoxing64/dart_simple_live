//! F-10 醒目留言列表（对照 Dart `huya_site.dart:546-556` + `huya_utils.dart:29-93`）。
//!
//! 链路：**先取房间详情拿 `topSid`，再拉 TUP 留言板**（Dart 注释「兼容 tv 接口 二次请求 detail」）。
//! `topSid == 0`（未开播 / 无直播参数）-> 返回空列表（对齐 Dart 的 `if (args.topSid != 0)`）。
//!
//! 过滤与排序口径（逐条对齐 Dart，勿改）：
//! - 文案 `trim()` 后为空 -> 丢弃；
//! - `remainSec = iCountDown > 0 ? iCountDown : iTotalSec`，`<= 0` -> 丢弃；
//! - `price = iCost`，为 0 且 `iCostPay > 0` 时取 `max(1, round(iCostPay / 100))`；
//! - `endTime = now + remainSec`，`startTime = endTime - totalSeconds`；
//! - 按 `startTime` **逆序**（最新在最前，见 issue #157 的口径变更）；
//! - `first = true` 时最多返回 10 条（`getSuperChatMessage` 走全量），否则只返回首条（弹幕增量）。

use chrono::{DateTime, Duration, Local};

use crate::error::SliveError;
use crate::models::LiveSuperChatMessage;

use super::danmaku::args::HuyaDanmakuArgs;
use super::danmaku::tars_sc::GameEventMessageBoardInfo;
use super::site::HuyaSite;

/// `first = true` 时的返回上限（对齐 Dart `messages.length > 10 ? sublist(0, 10)`）。
const FIRST_LIMIT: usize = 10;
/// 醒目留言背景色（对齐 Dart 字面量）。
const SC_BACKGROUND_COLOR: &str = "#ffffff";
/// 醒目留言底部色（对齐 Dart 字面量）。
const SC_BACKGROUND_BOTTOM_COLOR: &str = "#246488";

/// F-10 房间 SC 列表（走详情 -> TUP 两步）。
pub(crate) async fn fetch(
    site: &HuyaSite,
    room_id: &str,
) -> Result<Vec<LiveSuperChatMessage>, SliveError> {
    let detail = site.get_room_detail(room_id.to_string()).await?;
    let args = parse_danmaku_args(&detail.danmaku_data)?;
    if args.top_sid == 0 {
        return Ok(Vec::new());
    }
    fetch_by_pid(site, args.top_sid, true).await
}

/// 解析弹幕参数（缺失 -> `Decode`，J-5：不静默兜底）。
fn parse_danmaku_args(raw: &Option<String>) -> Result<HuyaDanmakuArgs, SliveError> {
    let json = raw
        .as_deref()
        .ok_or_else(|| SliveError::decode("房间详情缺少弹幕参数，无法定位直播间"))?;
    HuyaDanmakuArgs::from_json(json)
}

/// 按 `topSid` 拉取 SC 列表。
///
/// `pub` 而非 `pub(crate)`：弹幕会话的增量 SC 钩子由桥层注入（core 不持有 HTTP 连接），
/// 故桥层 crate 需要调用本函数（对齐 B站 `BilibiliSite::with_deps` 的可注入口径）。
pub async fn fetch_by_pid(
    site: &HuyaSite,
    pid: i64,
    first: bool,
) -> Result<Vec<LiveSuperChatMessage>, SliveError> {
    let rsp = super::tup::fetch_message_board(site, pid).await?;
    let now = Local::now();
    Ok(normalize(
        &rsp.t_message_board_panel.v_info,
        now,
        first,
    ))
}

/// 过滤 / 换算 / 排序（纯函数，便于夹具测试）。
pub(crate) fn normalize(
    items: &[GameEventMessageBoardInfo],
    now: DateTime<Local>,
    first: bool,
) -> Vec<LiveSuperChatMessage> {
    let mut messages: Vec<LiveSuperChatMessage> = items
        .iter()
        .filter_map(|item| to_message(item, now))
        .collect();

    // 对齐 Dart：最新在最前（降序）
    messages.sort_by_key(|m| std::cmp::Reverse(m.start_time));

    if first {
        if messages.len() > FIRST_LIMIT {
            messages.truncate(FIRST_LIMIT);
        }
        messages
    } else {
        // 增量：只返回首条（对齐 Dart 的 `[messages.first]`）
        messages.into_iter().take(1).collect()
    }
}

/// 单条换算；不满足条件的返回 `None`（丢弃）。
fn to_message(
    item: &GameEventMessageBoardInfo,
    now: DateTime<Local>,
) -> Option<LiveSuperChatMessage> {
    let content = item.s_content.trim();
    if content.is_empty() {
        return None;
    }
    let remain_secs = if item.i_count_down > 0 {
        item.i_count_down
    } else {
        item.i_total_sec
    };
    if remain_secs <= 0 {
        return None;
    }
    let total_secs = if item.i_total_sec > 0 {
        item.i_total_sec
    } else {
        remain_secs
    };

    let mut price = item.i_cost;
    if price <= 0 && item.i_cost_pay > 0 {
        // Dart: max(1, (iCostPay / 100).round())
        price = ((item.i_cost_pay as f64 / 100.0).round() as i64).max(1);
    }

    let end_time = now + Duration::seconds(remain_secs);
    let start_time = end_time - Duration::seconds(total_secs);

    Some(LiveSuperChatMessage {
        user_name: item.t_message_user.s_nick.trim().to_string(),
        face: item.t_message_user.s_avatar.clone(),
        message: content.to_string(),
        price: price as i32,
        start_time,
        end_time,
        background_color: SC_BACKGROUND_COLOR.to_string(),
        background_bottom_color: SC_BACKGROUND_BOTTOM_COLOR.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::platforms::huya::danmaku::tars_sc::MessageUser;

    fn item(
        content: &str,
        cost: i64,
        total_sec: i64,
        count_down: i64,
        cost_pay: i64,
        nick: &str,
    ) -> GameEventMessageBoardInfo {
        GameEventMessageBoardInfo {
            t_message_user: MessageUser {
                s_nick: nick.to_string(),
                s_avatar: "https://img/f.jpg".to_string(),
            },
            s_content: content.to_string(),
            i_cost: cost,
            i_total_sec: total_sec,
            i_count_down: count_down,
            l_message_id: 1,
            i_cost_pay: cost_pay,
        }
    }

    fn now() -> DateTime<Local> {
        Local::now()
    }

    #[test]
    fn keeps_valid_messages() {
        let list = normalize(
            &[item("上头条", 100, 60, 30, 0, " 金主 ")],
            now(),
            true,
        );
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].message, "上头条");
        assert_eq!(list[0].user_name, "金主", "昵称 trim");
        assert_eq!(list[0].price, 100);
        assert_eq!(list[0].background_color, "#ffffff");
        assert_eq!(list[0].background_bottom_color, "#246488");
    }

    #[test]
    fn drops_empty_and_expired_messages() {
        let list = normalize(
            &[
                item("   ", 100, 60, 30, 0, "n"),
                item("过期", 100, 0, 0, 0, "n"),
            ],
            now(),
            true,
        );
        assert!(list.is_empty(), "空文案与零剩余时长都要丢弃");
    }

    #[test]
    fn price_falls_back_to_cost_pay_cents() {
        // iCostPay = 12345 分 -> 123.45 -> round -> 123
        let list = normalize(&[item("x", 0, 60, 30, 12345, "n")], now(), true);
        assert_eq!(list[0].price, 123);
        // 极小金额兜底为 1
        let list = normalize(&[item("x", 0, 60, 30, 50, "n")], now(), true);
        assert_eq!(list[0].price, 1);
    }

    #[test]
    fn time_window_derives_start_from_end() {
        let base = now();
        let list = normalize(&[item("x", 1, 120, 60, 0, "n")], base, true);
        // end = base + 60s, start = end - 120s = base - 60s
        assert_eq!(list[0].end_time.timestamp(), base.timestamp() + 60);
        assert_eq!(list[0].start_time.timestamp(), base.timestamp() - 60);
    }

    #[test]
    fn falls_back_to_total_seconds_when_countdown_missing() {
        let base = now();
        let list = normalize(&[item("x", 1, 90, 0, 0, "n")], base, true);
        assert_eq!(list[0].end_time.timestamp(), base.timestamp() + 90);
        assert_eq!(list[0].start_time.timestamp(), base.timestamp());
    }

    #[test]
    fn sorts_newest_first() {
        let base = now();
        let old = item("旧", 1, 60, 10, 0, "n"); // end = base+10 -> start = base-50
        let new = item("新", 1, 60, 50, 0, "n"); // end = base+50 -> start = base-10
        let list = normalize(&[old, new], base, true);
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].message, "新", "最新在最前");
    }

    #[test]
    fn first_mode_truncates_to_ten() {
        let items: Vec<_> = (0..15)
            .map(|i| item(&format!("m{i}"), 1, 600, 60 + i, 0, "n"))
            .collect();
        let list = normalize(&items, now(), true);
        assert_eq!(list.len(), FIRST_LIMIT);
    }

    #[test]
    fn incremental_mode_returns_single_newest() {
        let items: Vec<_> = (0..5)
            .map(|i| item(&format!("m{i}"), 1, 600, 60 + i, 0, "n"))
            .collect();
        let list = normalize(&items, now(), false);
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].message, "m4", "增量取最新一条");
    }

    #[test]
    fn missing_danmaku_args_is_decode_error() {
        let err = parse_danmaku_args(&None).expect_err("缺参数");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }
}