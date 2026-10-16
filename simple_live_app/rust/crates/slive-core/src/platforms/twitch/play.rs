//! F-07 清晰度 / F-08 播放地址（对照 `twitch_site.dart:89-199`）。
//!
//! Twitch 取流是两步（与 B站/虎牙都不同）：
//! 1. GQL `PlaybackAccessToken` 拿 `value`（token）+ `signature`（sig）；
//! 2. 带 token/sig 访问 usher 的 m3u8 主播放列表，**从文本里解析线路与带宽**。
//!
//! 关键行为对齐点：
//! - **未开播时返回空列表**（Dart `if (liveStatus)` 才组装 qualities），不报错；
//! - `quality.data` 存**播放 URL 本身**（Dart 就是这么干的：它没有独立的取流接口，
//!   `getPlayUrls` 只是把 URL 包一层并附上 headers）；
//! - `play_session_id` 从两个候选中随机取（Dart `playSessionIds[random]`）；
//!   Rust 用注入时间源派生下标，保证离线可断言且仍随时间变化。
//! - `p` 参数：Dart 写的是 `DateTime.timestamp().second`（0~59 的**秒字段**，非时间戳），
//!   这是一个显式的实现怪癖但仅为缓存击穿参数；Rust 用 Unix 秒并在文档登记差异。

use std::collections::HashMap;

use crate::error::SliveError;
use crate::models::{LivePlayQuality, LivePlayUrl, LiveRoomDetail};

use super::gql::{build_persisted_request, PLAYBACK_ACCESS_TOKEN_HASH};
use super::header::request_header;
use super::m3u8::{parse_variants, quality_name};
use super::site::TwitchSite;

/// m3u8 主播放列表端点前缀（对齐 `twitch_site.dart:135`）。
const PLAY_URL_PREFIX: &str = "https://usher.ttvnw.net/api/channel/hls/";
/// 候选 `play_session_id`（对齐 `twitch_site.dart:34`）。
const PLAY_SESSION_IDS: [&str; 2] = [
    "bdd22331a986c7f1073628f2fc5b19da",
    "064bc3ff1722b6f53b0b5b8c01e46ca5",
];

/// F-07 清晰度列表（每项 `data` 即 m3u8 线路 URL）。
pub(crate) async fn fetch_qualities(
    site: &TwitchSite,
    detail: &LiveRoomDetail,
) -> Result<Vec<LivePlayQuality>, SliveError> {
    // Dart 无条件先取 token（即使未开播），保持同请求序列，避免行为漂移。
    let (token, signature) = fetch_access_token(site, &detail.room_id).await?;

    if !detail.status {
        return Ok(Vec::new());
    }

    let content = fetch_master_playlist(site, &detail.room_id, &token, &signature).await?;
    Ok(parse_variants(&content)
        .into_iter()
        .map(|variant| LivePlayQuality {
            quality: quality_name(variant.bandwidth).to_string(),
            data: variant.url,
            sort: i32::try_from(variant.bandwidth).unwrap_or(i32::MAX),
        })
        .collect())
}

/// F-08 播放地址：`quality.data` 已是线路 URL，本步只补请求头（对齐 Dart `getPlayUrls`）。
pub(crate) fn fetch_urls(
    site: &TwitchSite,
    _detail: &LiveRoomDetail,
    quality: &LivePlayQuality,
) -> Result<LivePlayUrl, SliveError> {
    if quality.data.trim().is_empty() {
        return Err(SliveError::invalid_input("Twitch 清晰度缺少播放地址".to_string()));
    }
    let headers = request_header(site).into_iter().collect::<HashMap<String, String>>();
    Ok(LivePlayUrl {
        urls: vec![quality.data.clone()],
        headers: Some(headers),
    })
}

/// GQL `PlaybackAccessToken` -> (token, signature)。
async fn fetch_access_token(
    site: &TwitchSite,
    room_id: &str,
) -> Result<(String, String), SliveError> {
    let query = build_persisted_request(
        "PlaybackAccessToken",
        PLAYBACK_ACCESS_TOKEN_HASH,
        serde_json::json!({
            "isLive": true,
            "login": room_id,
            "isVod": false,
            "vodID": "",
            "playerType": "site",
            "isClip": false,
            "clipID": "",
            "platform": "site",
        }),
    );
    let value = site.post_gql(&query).await?;
    let token_node = value
        .pointer("/data/streamPlaybackAccessToken")
        .ok_or_else(|| SliveError::decode("Twitch GQL 未返回 streamPlaybackAccessToken".to_string()))?;
    let token = token_node
        .get("value")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| SliveError::decode("Twitch GQL 未返回 token".to_string()))?
        .to_string();
    let signature = token_node
        .get("signature")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| SliveError::decode("Twitch GQL 未返回 signature".to_string()))?
        .to_string();
    Ok((token, signature))
}

/// 拉取 usher m3u8 主播放列表文本。
///
/// 请求头与 GQL **同一套**（对齐 Dart：两处都传 `headers`），不额外替换 UA ——
/// Dart 的 `getText(m3u8Url, queryParameters: params, header: headers)` 用的是站点头。
async fn fetch_master_playlist(
    site: &TwitchSite,
    room_id: &str,
    token: &str,
    signature: &str,
) -> Result<String, SliveError> {
    let play_session_id = play_session_id(site.time().unix_secs());
    let p = site.time().unix_secs().to_string();
    let query = vec![
        ("acmb".to_string(), "e30=".to_string()),
        ("allow_source".to_string(), "true".to_string()),
        ("cdm".to_string(), "wv".to_string()),
        ("fast_bread".to_string(), "true".to_string()),
        ("p".to_string(), p),
        ("platform".to_string(), "web".to_string()),
        ("play_session_id".to_string(), play_session_id.to_string()),
        ("player_backend".to_string(), "mediaplayer".to_string()),
        ("player_version".to_string(), "1.28.0-rc.1".to_string()),
        ("playlist_include_framerate".to_string(), "true".to_string()),
        ("reassignments_supported".to_string(), "true".to_string()),
        ("sig".to_string(), signature.to_string()),
        ("token".to_string(), token.to_string()),
        ("transcode_mode".to_string(), "cbr_v1".to_string()),
    ];
    site.get_text(&format!("{PLAY_URL_PREFIX}{room_id}.m3u8"), query)
        .await
}

/// 由时间源派生 `play_session_id` 下标（Dart 为随机取其一；此处确定性可测）。
fn play_session_id(unix_secs: u64) -> &'static str {
    PLAY_SESSION_IDS[(unix_secs % PLAY_SESSION_IDS.len() as u64) as usize]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn play_session_id_alternates_by_time() {
        let a = play_session_id(0);
        let b = play_session_id(1);
        assert_ne!(a, b, "相邻秒应命中不同候选");
        assert!(PLAY_SESSION_IDS.contains(&a) && PLAY_SESSION_IDS.contains(&b));
    }

    #[test]
    fn play_session_id_is_stable_within_same_second() {
        assert_eq!(play_session_id(42), play_session_id(42));
    }
}
