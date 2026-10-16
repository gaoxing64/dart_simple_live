//! F-07 清晰度列表 / F-08 播放地址（对照 `bilibili_site.dart:117-192`）。

use std::collections::HashMap;

use crate::error::SliveError;
use crate::http::{check_api_code, PLAY_REFERER, PLAY_USER_AGENT};
use crate::models::{LivePlayQuality, LivePlayUrl, LiveRoomDetail};
use crate::util::as_i32;

use super::site::BilibiliSite;
use super::util::text;

const PLAY_URL: &str = "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo";
const UNKNOWN_QUALITY: &str = "未知清晰度";

/// F-07 清晰度列表：由 `g_qn_desc` 映射 `accept_qn`；无法映射 -> `未知清晰度`。
pub(crate) async fn fetch_qualities(
    site: &BilibiliSite,
    detail: &LiveRoomDetail,
) -> Result<Vec<LivePlayQuality>, SliveError> {
    let query = vec![
        ("room_id".to_string(), detail.room_id.clone()),
        ("protocol".to_string(), "0,1".to_string()),
        ("format".to_string(), "0,1,2".to_string()),
        ("codec".to_string(), "0,1".to_string()),
        ("platform".to_string(), "web".to_string()),
    ];
    let value = site.get_json(PLAY_URL, query).await?;
    check_api_code(&value)?;

    let mut desc_map: HashMap<i32, String> = HashMap::new();
    for item in crate::util::array_at(&value, "/data/playurl_info/playurl/g_qn_desc") {
        if let Some(qn) = as_i32(item.get("qn")) {
            desc_map.insert(qn, text(item, "desc"));
        }
    }

    let accept = crate::util::array_at(
        &value,
        "/data/playurl_info/playurl/stream/0/format/0/codec/0/accept_qn",
    );
    Ok(accept
        .iter()
        .enumerate()
        .map(|(index, qn_value)| {
            let qn = as_i32(Some(qn_value)).unwrap_or(0);
            LivePlayQuality {
                quality: desc_map
                    .get(&qn)
                    .cloned()
                    .unwrap_or_else(|| UNKNOWN_QUALITY.to_string()),
                data: qn.to_string(),
                sort: index as i32,
            }
        })
        .collect())
}

/// F-08 播放地址：`host+base_url+extra`，含 `mcdn` 的线路**后置**（AC-08）。
pub(crate) async fn fetch_urls(
    site: &BilibiliSite,
    detail: &LiveRoomDetail,
    quality: &LivePlayQuality,
) -> Result<LivePlayUrl, SliveError> {
    let qn: i32 = quality
        .data
        .trim()
        .parse()
        .map_err(|_| SliveError::invalid_input(format!("非法清晰度 qn: {}", quality.data)))?;

    let query = vec![
        ("room_id".to_string(), detail.room_id.clone()),
        ("protocol".to_string(), "0,1".to_string()),
        ("format".to_string(), "0,2".to_string()),
        ("codec".to_string(), "0".to_string()),
        ("platform".to_string(), "web".to_string()),
        ("qn".to_string(), qn.to_string()),
    ];
    let value = site.get_json(PLAY_URL, query).await?;
    check_api_code(&value)?;

    let mut urls = Vec::new();
    for stream in crate::util::array_at(&value, "/data/playurl_info/playurl/stream") {
        for format in crate::util::array_at(stream, "/format") {
            for codec in crate::util::array_at(format, "/codec") {
                let base_url = text(codec, "base_url");
                for url_info in crate::util::array_at(codec, "/url_info") {
                    urls.push(format!(
                        "{}{}{}",
                        text(url_info, "host"),
                        base_url,
                        text(url_info, "extra")
                    ));
                }
            }
        }
    }
    // 对链接排序：包含 mcdn 的在后（稳定排序，保持各自原有相对顺序）。
    urls.sort_by_key(|url| url.contains("mcdn"));

    let headers = HashMap::from([
        ("referer".to_string(), PLAY_REFERER.to_string()),
        ("user-agent".to_string(), PLAY_USER_AGENT.to_string()),
    ]);
    Ok(LivePlayUrl {
        urls,
        headers: Some(headers),
    })
}
