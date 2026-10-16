//! F-06 房间详情（对照 `huya_site.dart:225-342`）。
//!
//! 房间页内嵌两段 JSON（都不是接口，必须正则抽取）：
//! - `TT_ROOM_DATA`：在播状态与录播标记；
//! - `stream:` 块：标题/封面/主播/**线路**/**清晰度**。
//!
//! 两个数据通道（对齐 Spec §4.4 与 B站口径）：
//! - `danmaku_data` = [`HuyaDanmakuArgs`] 的 JSON 串；
//! - `data` = [`HuyaUrlDataModel`] 的 JSON 串（仅在播时有）。
//!
//! 关键行为对齐（勿"顺手修正"）：
//! - **未开播也必须填 `danmaku_data`**（三 id 全 0）—— App 无论是否在播都会
//!   `liveDanmaku.start(detail.danmakuData)`，缺失会抛 `type 'Null' is not a subtype`；
//! - `TT_ROOM_DATA` 抓不到时 Dart 抛 `LateInitializationError`（`late result` 未赋值）
//!   → Rust 侧返回 `SliveError::Decode`（J-5：类型化错误，不静默兜底）；
//! - 抽到但 JSON 非法时 Dart 只记日志并返回未初始化的 `result`（实际会抛）
//!   → Rust 侧同样按 `Decode` 处理，避免"半成品详情"流到下游。

use serde_json::Value;

use crate::error::SliveError;
use crate::models::LiveRoomDetail;
use crate::util::{as_i32, as_i64};

use super::common::BASE_URL;
use super::danmaku::args::HuyaDanmakuArgs;
use super::detail_parse::{parse_bit_rates, parse_lines, text};
use super::models::HuyaUrlDataModel;
use super::site::HuyaSite;
use super::status::{extract_room_data, is_live};
use super::utils::get_uid;

/// F-06 房间详情。
pub(crate) async fn fetch(site: &HuyaSite, room_id: &str) -> Result<LiveRoomDetail, SliveError> {
    let page = site
        .get_text(&format!("{BASE_URL}/{room_id}"), Vec::new())
        .await?;
    parse_room_detail(room_id, &page)
}

/// 从房间页文本解析详情（纯函数，便于夹具测试）。
pub(crate) fn parse_room_detail(
    room_id: &str,
    page: &str,
) -> Result<LiveRoomDetail, SliveError> {
    let room_data_raw = extract_room_data(page).ok_or_else(|| {
        SliveError::decode(format!("房间页未内嵌 TT_ROOM_DATA: room_id={room_id}"))
    })?;
    let room_data: Value = serde_json::from_str(&room_data_raw)
        .map_err(|e| SliveError::decode(format!("TT_ROOM_DATA 解析失败: {e}")))?;
    let stream_data: Value = serde_json::from_str(&super::detail_parse::extract_stream(page)?)
        .map_err(|e| SliveError::decode(format!("stream 数据解析失败: {e}")))?;

    let live_info = stream_data
        .pointer("/data/0/gameLiveInfo")
        .cloned()
        .ok_or_else(|| SliveError::decode("stream 数据缺少 data[0].gameLiveInfo"))?;
    let status = is_live(&room_data);
    let introduction = text(&live_info, "introduction");

    let mut detail = LiveRoomDetail {
        room_id: room_id.to_string(),
        title: introduction.clone(),
        cover: text(&live_info, "screenshot"),
        user_name: text(&live_info, "nick"),
        user_avatar: text(&live_info, "avatar180"),
        online: as_i32(live_info.get("totalCount")).unwrap_or(0),
        introduction: Some(introduction.clone()),
        notice: Some(introduction),
        status,
        data: None,
        // 默认未开播占位；下方按分支覆盖
        danmaku_data: Some(HuyaDanmakuArgs::offline().to_json()?),
        is_record: room_data
            .get("isReplay")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        url: format!("https://www.huya.com/{room_id}"),
    };

    if !status {
        // 未开播：保留全 0 弹幕参数，不产出取流数据
        return Ok(detail);
    }

    // 在播：解析弹幕参数（id 可能是 int 或 string，Dart 用 int.tryParse 兜底）
    let stream_info = stream_data
        .pointer("/data/0/gameStreamInfoList/0")
        .ok_or_else(|| SliveError::decode("stream 数据缺少 gameStreamInfoList[0]"))?;
    let top_sid = as_i64(stream_info.get("lChannelId")).unwrap_or(0);
    let sub_sid = as_i64(stream_info.get("lSubChannelId")).unwrap_or(0);
    let ayyuid = as_i64(live_info.get("uid")).unwrap_or(0);
    detail.danmaku_data = Some(
        HuyaDanmakuArgs::new(ayyuid, top_sid, sub_sid).to_json()?,
    );

    let url_data = HuyaUrlDataModel {
        url: "huya need rebuild new url".to_string(),
        uid: get_uid(Some(13), Some(10)),
        lines: parse_lines(&stream_data, top_sid),
        bit_rates: parse_bit_rates(&stream_data),
    };
    detail.data = Some(url_data.to_json()?);
    Ok(detail)
}



#[cfg(test)]
mod tests {
    use super::*;
    use crate::platforms::huya::models::HuyaLineType;
    use serde_json::json;

    fn live_info(introduction: &str) -> Value {
        json!({
            "gameLiveInfo": {
                "introduction": introduction,
                "screenshot": "https://img/cover.jpg",
                "nick": "主播A",
                "avatar180": "https://img/avatar.jpg",
                "totalCount": 1234,
                "uid": "998877"
            }
        })
    }

    /// 构造房间页 HTML。
    ///
    /// ⚠️ `stream:` 的 JSON 必须**单行**，且之后紧跟「换行 + `}`」——
    /// Dart 的 `STREAM_REGEX` 以 `\n\s*\}` 收尾，且 `split('\n')[0]` 只取首行
    /// （QA 夹具契约，见 `18-fixtures-multiplatform.md §3.2`）。
    /// 组装房间页 HTML（`stream` 块由调用方给完整结构）。
    ///
    /// ⚠️ `stream:` 的 JSON 必须**单行**，且之后紧跟「换行 + `}`」——
    /// Dart 的 `STREAM_REGEX` 以 `\n\s*\}` 收尾，且 `split('\n')[0]` 只取首行
    /// （QA 夹具契约，见 `18-fixtures-multiplatform.md §3.2`）。
    fn page_with_stream(room_data: &str, stream: Value) -> String {
        format!(
            "<html><script>var TT_ROOM_DATA = {room_data};</script>\n<script>\nstream: {}\n}}</script></html>",
            serde_json::to_string(&stream).expect("序列化")
        )
    }

    /// 仅给 `gameLiveInfo` 的简化页面（未开播 / 回放等分支用）。
    fn live_page(live_info: Value, room_data: &str) -> String {
        let stream = json!({
            "data": [{"gameLiveInfo": live_info, "gameStreamInfoList": []}],
            "vMultiStreamInfo": [],
        });
        page_with_stream(room_data, stream)
    }

    fn full_live_page() -> String {
        let stream = json!({
            "data": [
                {
                    "gameLiveInfo": {
                        "introduction": "精彩直播",
                        "screenshot": "https://img/cover.jpg",
                        "nick": "主播A",
                        "avatar180": "https://img/avatar.jpg",
                        "totalCount": 1234,
                        "uid": "998877"
                    },
                    "gameStreamInfoList": [
                        {
                            "sFlvUrl": "https://cdn/flv",
                            "sHlsUrl": "https://cdn/hls",
                            "sFlvAntiCode": "fa",
                            "sHlsAntiCode": "ha",
                            "sStreamName": "stream1",
                            "sCdnType": "1",
                            "lChannelId": "111",
                            "lSubChannelId": "222"
                        },
                        {
                            "sFlvUrl": "",
                            "sHlsUrl": "https://cdn2/hls",
                            "sStreamName": "stream2",
                            "sCdnType": "2",
                            "lChannelId": 333,
                            "lSubChannelId": 444
                        }
                    ]
                }
            ],
            "vMultiStreamInfo": [
                {"sDisplayName": "原画", "iBitRate": 0},
                {"sDisplayName": "蓝光", "iBitRate": 2000},
                {"sDisplayName": "HDR 超清", "iBitRate": 4000},
                {"sDisplayName": "4K", "iBitRate": 6000}
            ]
        });
        page_with_stream(r#"{"state":"ON","isReplay":false}"#, stream)
    }

    #[test]
    fn live_detail_maps_all_fields() {
        let detail = parse_room_detail("660000", &full_live_page()).expect("解析详情");
        assert_eq!(detail.room_id, "660000");
        assert_eq!(detail.title, "精彩直播");
        assert_eq!(detail.cover, "https://img/cover.jpg");
        assert_eq!(detail.user_name, "主播A");
        assert_eq!(detail.user_avatar, "https://img/avatar.jpg");
        assert_eq!(detail.online, 1234);
        assert_eq!(detail.introduction.as_deref(), Some("精彩直播"));
        assert_eq!(detail.notice.as_deref(), Some("精彩直播"));
        assert!(detail.status);
        assert!(!detail.is_record);
        assert_eq!(detail.url, "https://www.huya.com/660000");
    }

    #[test]
    fn live_detail_carries_danmaku_args_and_url_data() {
        let detail = parse_room_detail("660000", &full_live_page()).expect("解析详情");
        let args =
            HuyaDanmakuArgs::from_json(detail.danmaku_data.as_deref().expect("弹幕参数"))
                .expect("弹幕参数可解析");
        assert_eq!(
            args,
            HuyaDanmakuArgs::new(998877, 111, 222),
            "id 允许 string/int 两种形态"
        );

        let data =
            HuyaUrlDataModel::from_json(detail.data.as_deref().expect("取流数据")).expect("取流数据");
        assert_eq!(data.uid.len(), 13);
        assert_eq!(data.lines.len(), 3, "流1 FLV+HLS，流2 仅 HLS");
        assert_eq!(data.lines[0].line_type, HuyaLineType::Flv);
        assert_eq!(data.lines[1].line_type, HuyaLineType::Hls);
        // Dart 对**所有**线路用同一个 topSid（取自 gameStreamInfoList[0]）
        assert_eq!(data.lines[0].presenter_uid, 111);
        assert_eq!(data.lines[2].presenter_uid, 111);
        assert_eq!(
            data.bit_rates.iter().map(|b| b.name.as_str()).collect::<Vec<_>>(),
            vec!["原画", "蓝光", "4K"],
            "HDR 被过滤，4K 保留（跳过发生在清晰度列表环节）"
        );
    }

    #[test]
    fn offline_detail_still_carries_placeholder_danmaku_args() {
        let page = live_page(live_info("休息中"), r#"{"state":"OFF","isReplay":false}"#);
        let detail = parse_room_detail("660000", &page).expect("解析详情");
        assert!(!detail.status);
        assert!(detail.data.is_none(), "未开播无取流数据");
        let args =
            HuyaDanmakuArgs::from_json(detail.danmaku_data.as_deref().expect("弹幕参数"))
                .expect("弹幕参数可解析");
        assert_eq!(args, HuyaDanmakuArgs::offline(), "未开播占位三 id 全 0");
        assert!(!args.is_live());
    }

    #[test]
    fn replay_room_is_not_live_and_recorded() {
        let page = live_page(live_info("录播"), r#"{"state":"ON","isReplay":true}"#);
        let detail = parse_room_detail("660000", &page).expect("解析详情");
        assert!(!detail.status, "录播不算在播");
        assert!(detail.is_record);
    }

    #[test]
    fn missing_room_data_is_decode_error() {
        let err = parse_room_detail("660000", "<html>无数据</html>").expect_err("必须报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn missing_stream_is_decode_error() {
        let page = "<script>var TT_ROOM_DATA = {\"state\":\"ON\",\"isReplay\":false};</script>".to_string();
        let err = parse_room_detail("660000", &page).expect_err("必须报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn malformed_room_data_is_decode_error() {
        let page = "<script>var TT_ROOM_DATA = {oops};</script>";
        let err = parse_room_detail("660000", page).expect_err("必须报错");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn empty_introduction_still_produces_detail() {
        let page = live_page(live_info(""), r#"{"state":"OFF","isReplay":false}"#);
        let detail = parse_room_detail("660000", &page).expect("解析详情");
        assert_eq!(detail.title, "");
        assert_eq!(detail.introduction.as_deref(), Some(""));
    }
}