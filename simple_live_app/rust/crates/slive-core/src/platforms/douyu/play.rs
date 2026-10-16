//! F-07 清晰度列表 / F-08 播放地址（对照 `douyu_site.dart:86-174`）。
//!
//! 两步协议（与 Dart 一致）：
//! 1. `getH5PlayV1/{roomId}` + `sign(rate=-1)` 一次拿到 **线路列表（cdns）** 与**清晰度列表（multirates）**；
//! 2. `getH5PlayV1/{roomId}` + `sign(rate=<选中>, cdn=<线路>)` 逐线路取直链。
//!
//! `LivePlayQuality.data` 承载 `DouyuPlayData{rate, cdns}`，按 §4.4 口径以 **JSON 串**往返
//! （B站存 `qn` 数字串，斗鱼存结构体；绑定层原样透传，不在 Dart 侧解析 —— J-10）。

use serde_json::Value;

use crate::error::SliveError;
use crate::models::{LivePlayQuality, LivePlayUrl, LiveRoomDetail};
use crate::util::as_i32;

use super::api_code::check_error_code;
use super::header::request_header;
use super::sign::{build_default_sign, build_sign};
use super::site::DouyuSite;
use super::util::{html_unescape, value_or_empty};

/// 取流端点。
const PLAY_URL: &str = "https://www.douyu.com/lapi/live/getH5PlayV1";
/// 线路排序时把 `scdn` 前缀的线路排到最后（对齐 Dart `cdns.sort`）。
const SCDN_PREFIX: &str = "scdn";

/// `quality.data` 的载荷（对应 Dart `DouyuPlayData`）。
#[derive(Debug, Clone, PartialEq, Eq)]
struct PlayData {
    rate: i32,
    cdns: Vec<String>,
}

impl PlayData {
    fn to_json(&self) -> String {
        serde_json::json!({ "rate": self.rate, "cdns": self.cdns }).to_string()
    }

    fn from_json(raw: &str) -> Result<Self, SliveError> {
        let value: Value = serde_json::from_str(raw).map_err(|e| {
            SliveError::invalid_input(format!("斗鱼清晰度数据不是合法 JSON: {e}"))
        })?;
        let rate = value
            .get("rate")
            .and_then(|v| as_i32(Some(v)))
            .ok_or_else(|| SliveError::invalid_input("斗鱼清晰度数据缺 rate 字段"))?;
        let cdns = value
            .get("cdns")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .map(crate::util::value_to_string)
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        Ok(Self { rate, cdns })
    }
}

/// F-07 清晰度列表（含线路列表，随 `quality.data` 一起下发）。
pub(crate) async fn fetch_qualities(
    site: &DouyuSite,
    detail: &LiveRoomDetail,
) -> Result<Vec<LivePlayQuality>, SliveError> {
    let data = build_default_sign(site, &detail.room_id).await?;
    let value = post_play(site, &detail.room_id, &data).await?;

    let cdns = sorted_cdns(&value);
    let mut qualities = Vec::new();
    for item in crate::util::array_at(&value, "/data/multirates") {
        let Some(rate) = item.get("rate").and_then(|v| as_i32(Some(v))) else {
            continue;
        };
        qualities.push(LivePlayQuality {
            quality: value_or_empty(item, "name"),
            data: PlayData {
                rate,
                cdns: cdns.clone(),
            }
            .to_json(),
            sort: qualities.len() as i32,
        });
    }
    Ok(qualities)
}

/// F-08 播放地址：逐线路取流 + 海外 expire 兜底。
pub(crate) async fn fetch_urls(
    site: &DouyuSite,
    detail: &LiveRoomDetail,
    quality: &LivePlayQuality,
) -> Result<LivePlayUrl, SliveError> {
    let data = PlayData::from_json(&quality.data)?;
    let mut urls = Vec::new();
    for cdn in &data.cdns {
        let url = fetch_url_for_cdn(site, &detail.room_id, data.rate, cdn).await?;
        // 空串表示该线路没取到直链（Dart: `if (url.isNotEmpty)` 跳过）
        if !url.is_empty() {
            urls.push(url);
        }
    }
    // O-7（直链续流 renewers）本批不做：需 FRB 回调通道，已登记待办。
    Ok(LivePlayUrl {
        urls,
        headers: None,
    })
}

/// 逐线路取直链：`{rtmp_url}/{htmlUnescape(rtmp_live)}` + 海外 expire 兜底。
///
/// 空串 = 该线路未取到直链（非错误，对齐 Dart 跳过该线路的语义）。
pub(crate) async fn fetch_url_for_cdn(
    site: &DouyuSite,
    room_id: &str,
    rate: i32,
    cdn: &str,
) -> Result<String, SliveError> {
    let sign = build_sign(site, room_id, rate, cdn).await?;
    let value = post_play(site, room_id, &sign).await?;
    Ok(apply_oversea_expire_workaround(&extract_stream_url(&value)))
}

/// 海外临时方案：`fcdn=ws` 且 `expire=300` 的直链追加 `expire=0`。
///
/// 上游标注为临时方案（Dart `_applyOverseaExpireWorkaround`）；**首次取流与续流必须走同一条规则**，
/// 否则续流拿回来的直链又变回 5 分钟寿命。
pub(crate) fn apply_oversea_expire_workaround(url: &str) -> String {
    if url.contains("expire=300") && url.contains("fcdn=ws") {
        format!("{url}&expire=0")
    } else {
        url.to_string()
    }
}

async fn post_play(site: &DouyuSite, room_id: &str, body: &str) -> Result<Value, SliveError> {
    let url = format!("{PLAY_URL}/{room_id}");
    let cookie = site.cookie();
    let value = site
        .post_form_json(url, body, request_header(site, room_id, &cookie, false))
        .await?;
    check_error_code(&value)?;
    Ok(value)
}

/// 线路列表：`scdn` 前缀的排到最后（其余保持原序 —— 稳定排序）。
fn sorted_cdns(value: &Value) -> Vec<String> {
    let mut cdns: Vec<String> = crate::util::array_at(value, "/data/cdnsWithName")
        .iter()
        .map(|item| value_or_empty(item, "cdn"))
        .filter(|cdn| !cdn.is_empty())
        .collect();
    cdns.sort_by_key(|cdn| cdn.starts_with(SCDN_PREFIX));
    cdns
}

fn extract_stream_url(value: &Value) -> String {
    let base = value
        .pointer("/data/rtmp_url")
        .map(crate::util::value_to_string)
        .unwrap_or_default();
    let live = value
        .pointer("/data/rtmp_live")
        .map(crate::util::value_to_string)
        .unwrap_or_default();
    if base.is_empty() || live.is_empty() {
        return String::new();
    }
    format!("{base}/{}", html_unescape(&live))
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::testing::{FakeTime, MockTransport};
    use super::super::transport::MockDouyuPost;

    const ENC_FIXTURE: &str = r#"{"error":0,"data":{"key":"K","rand_str":"R","enc_time":1,"is_special":0,"enc_data":"E"}}"#;
    const QUALITY_FIXTURE: &str = r#"{"error":0,"data":{
        "cdnsWithName":[{"cdn":"scdn-a"},{"cdn":"tct-h5"},{"cdn":"ali-h5"}],
        "multirates":[{"name":"原画","rate":0},{"name":"蓝光","rate":4}]
    }}"#;

    fn site(play_body: &str) -> (DouyuSite, Arc<MockTransport>, Arc<MockDouyuPost>) {
        let mock = Arc::new(MockTransport::new());
        mock.stub("getEncryption", ENC_FIXTURE);
        let post = Arc::new(MockDouyuPost::new());
        post.stub("getH5PlayV1", play_body);
        let s = DouyuSite::with_deps(
            mock.clone(),
            post.clone(),
            Arc::new(FakeTime::new(1_700_000_000)),
        );
        (s, mock, post)
    }

    fn detail() -> LiveRoomDetail {
        LiveRoomDetail {
            room_id: "999".into(),
            title: String::new(),
            cover: String::new(),
            user_name: String::new(),
            user_avatar: String::new(),
            online: 0,
            introduction: None,
            notice: None,
            status: true,
            data: None,
            danmaku_data: None,
            is_record: false,
            url: "https://www.douyu.com/999".into(),
        }
    }

    #[tokio::test]
    async fn qualities_carry_rate_and_sorted_cdns() {
        let (s, _mock, _post) = site(QUALITY_FIXTURE);
        let qualities = s
            .get_play_qualities(detail())
            .await
            .expect("清晰度应成功");

        assert_eq!(qualities.len(), 2);
        assert_eq!(qualities[0].quality, "原画");
        assert_eq!(qualities[0].sort, 0);
        let data = PlayData::from_json(&qualities[0].data).expect("data 可往返");
        assert_eq!(data.rate, 0);
        assert_eq!(
            data.cdns,
            vec!["tct-h5", "ali-h5", "scdn-a"],
            "scdn 前缀线路必须排到最后"
        );
        assert_eq!(PlayData::from_json(&qualities[1].data).expect("往返").rate, 4);
    }

    #[tokio::test]
    async fn urls_are_fetched_per_cdn_with_oversea_expire_hack() {
        let (s, _mock, post) = site(
            r#"{"error":0,"data":{"rtmp_url":"https://tcdn.example/live","rtmp_live":"a.flv?expire=300&amp;fcdn=ws"}}"#,
        );
        let quality = LivePlayQuality {
            quality: "原画".into(),
            data: PlayData {
                rate: 0,
                cdns: vec!["tct-h5".into(), "ali-h5".into()],
            }
            .to_json(),
            sort: 0,
        };
        let result = s
            .get_play_urls(detail(), quality)
            .await
            .expect("取流应成功");

        assert_eq!(result.urls.len(), 2);
        assert_eq!(
            result.urls[0],
            "https://tcdn.example/live/a.flv?expire=300&fcdn=ws&expire=0",
            "HTML 实体需反转义，且海外线路要追加 expire=0"
        );
        assert_eq!(post.request_count("getH5PlayV1"), 2, "每条线路各取一次");
    }

    #[tokio::test]
    async fn non_oversea_url_is_untouched() {
        let (s, _mock, _post) = site(
            r#"{"error":0,"data":{"rtmp_url":"https://tcdn.example/live","rtmp_live":"a.flv?expire=300&cdn=ws-h5"}}"#,
        );
        let url = fetch_url_for_cdn(&s, "999", 0, "ws-h5")
            .await
            .expect("取流应成功");
        assert_eq!(url, "https://tcdn.example/live/a.flv?expire=300&cdn=ws-h5");
    }

    #[tokio::test]
    async fn business_error_is_api_error_without_retry() {
        let (s, _mock, post) = site(r#"{"error":1004,"msg":"房间未开播"}"#);
        let err = s
            .get_play_qualities(detail())
            .await
            .expect_err("error!=0 必须抛错");
        match err {
            SliveError::Api { code, message } => {
                assert_eq!(code, 1004);
                assert_eq!(message, "房间未开播");
            }
            other => panic!("期望 SliveError::Api，实际 {other:?}"),
        }
        assert_eq!(post.request_count("getH5PlayV1"), 1, "业务错误不得重试");
    }

    #[tokio::test]
    async fn malformed_quality_data_is_invalid_input() {
        let (s, _mock, _post) = site(QUALITY_FIXTURE);
        let quality = LivePlayQuality {
            quality: "坏数据".into(),
            data: "not-json".into(),
            sort: 0,
        };
        let err = s
            .get_play_urls(detail(), quality)
            .await
            .expect_err("非法 data 必须报错");
        assert!(matches!(err, SliveError::InvalidInput(_)), "实际 {err:?}");
    }

    #[test]
    fn missing_stream_fields_yield_empty_url() {
        assert_eq!(extract_stream_url(&serde_json::json!({})), "");
        assert_eq!(
            extract_stream_url(&serde_json::json!({"data":{"rtmp_url":"u"}})),
            "",
            "缺 rtmp_live 时不拼半截 URL"
        );
    }
}