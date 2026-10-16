//! F-07 清晰度列表（对照 `huya_site.dart:132-161`）。
//!
//! 本模块**纯本地计算**，不发请求（清晰度来自 F-06 详情内嵌的 `vMultiStreamInfo`）。
//!
//! 两条业务规则（对齐 Dart，勿改）：
//! - `bitRates` 为空时兜底为 `[原画/0, 高清/2000]`（服务端偶尔不下发）；
//! - **跳过 `4K`**：4K 需 VIP 房间（虎牙官方说明），Dart 无条件跳过，
//!   `is_vip_room` 仅作为可观测判定暴露（见 [`crate::platforms::huya::vip_room_id`]）。

use crate::error::SliveError;
use crate::models::{LivePlayQuality, LivePlayUrl, LiveRoomDetail};

use super::anti_code::{build_anti_code, build_play_url};
use super::models::{HuyaBitRateModel, HuyaQualityData, HuyaUrlDataModel};
use super::site::HuyaSite;

/// 空清晰度时的兜底（原画 + 高清）。
fn fallback_bitrates() -> Vec<HuyaBitRateModel> {
    vec![
        HuyaBitRateModel {
            name: "原画".to_string(),
            bit_rate: 0,
        },
        HuyaBitRateModel {
            name: "高清".to_string(),
            bit_rate: 2000,
        },
    ]
}

/// F-07 清晰度列表。
pub(crate) fn fetch_qualities(
    _site: &HuyaSite,
    detail: &LiveRoomDetail,
) -> Result<Vec<LivePlayQuality>, SliveError> {
    let data = parse_url_data(detail)?;
    let bit_rates = if data.bit_rates.is_empty() {
        fallback_bitrates()
    } else {
        data.bit_rates.clone()
    };

    let mut out = Vec::with_capacity(bit_rates.len());
    for (index, item) in bit_rates.iter().enumerate() {
        // 4K 需 VIP，Dart 直接跳过
        if item.name == "4K" {
            continue;
        }
        out.push(LivePlayQuality {
            quality: item.name.clone(),
            data: HuyaQualityData {
                urls: data.lines.clone(),
                bit_rate: item.bit_rate,
            }
            .to_json()?,
            sort: index as i32,
        });
    }
    Ok(out)
}

/// 解析 `detail.data`；缺失或非法 -> `Decode`（J-5：不做静默兜底）。
pub(crate) fn parse_url_data(detail: &LiveRoomDetail) -> Result<HuyaUrlDataModel, SliveError> {
    let raw = detail
        .data
        .as_deref()
        .ok_or_else(|| SliveError::decode("房间详情缺少取流数据（未开播？）"))?;
    HuyaUrlDataModel::from_json(raw)
}

/// F-08 播放地址：逐线路换 TARS token + 反 anticode 后拼 URL。
///
/// 失败口径（对齐 Dart `getPlayUrls`）：**单条线路失败只记日志并跳过**，
/// 全部失败才返回错误 —— 一条线路被 403 不应让整个房间不可播。
pub(crate) async fn fetch_urls(
    site: &HuyaSite,
    _detail: &LiveRoomDetail,
    quality: &LivePlayQuality,
) -> Result<LivePlayUrl, SliveError> {
    let quality_data = HuyaQualityData::from_json(&quality.data)?;
    let mut urls: Vec<String> = Vec::with_capacity(quality_data.urls.len());

    for line in &quality_data.urls {
        match build_line_url(site, line, quality_data.bit_rate).await {
            Ok(url) => urls.push(url),
            Err(e) => {
                // 单线失败跳过（Dart: catch 后 CoreLog.e）
                log::debug!("虎牙取流跳过线路 {}: {e}", line.line);
            }
        }
    }

    if urls.is_empty() {
        return Err(SliveError::Api {
            code: -1,
            message: "虎牙取流失败：所有线路均不可用".to_string(),
        });
    }

    let headers = std::collections::HashMap::from([(
        "user-agent".to_string(),
        site.hysdk_ua(),
    )]);
    Ok(LivePlayUrl {
        urls,
        headers: Some(headers),
    })
}

/// 单条线路的取流地址：换 token -> 反 anticode -> 拼 URL。
async fn build_line_url(
    site: &HuyaSite,
    line: &super::models::HuyaLineModel,
    bit_rate: i32,
) -> Result<String, SliveError> {
    let token = super::tup::fetch_cdn_token(site, &line.stream_name).await?;
    // 反 anticode（无 fm 时原样返回 token —— Dart 口径）
    let anti = build_anti_code(
        &token,
        &line.stream_name,
        line.presenter_uid,
        site.now_millis(),
    )
    .map_err(SliveError::decode)?
    .unwrap_or_else(|| token.clone());
    build_play_url(
        &line.line,
        &line.stream_name,
        line.line_type.is_hls(),
        &anti,
        bit_rate,
    )
    .map_err(SliveError::decode)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeTime, MockTransport};
    use std::sync::Arc;

    fn site() -> HuyaSite {
        HuyaSite::with_get_deps(
            Arc::new(MockTransport::new()),
            Arc::new(FakeTime::new(1_700_000_000)),
        )
    }

    fn detail_with(bit_rates: Vec<HuyaBitRateModel>) -> LiveRoomDetail {
        let data = HuyaUrlDataModel {
            url: "huya need rebuild new url".to_string(),
            uid: "0000000000000".to_string(),
            lines: vec![],
            bit_rates,
        };
        LiveRoomDetail {
            room_id: "660000".to_string(),
            title: "t".to_string(),
            cover: String::new(),
            user_name: "u".to_string(),
            user_avatar: String::new(),
            online: 1,
            introduction: None,
            notice: None,
            status: true,
            data: Some(data.to_json().expect("序列化")),
            danmaku_data: None,
            is_record: false,
            url: String::new(),
        }
    }

    #[test]
    fn qualities_skip_4k_and_keep_order() {
        let detail = detail_with(vec![
            HuyaBitRateModel {
                name: "原画".to_string(),
                bit_rate: 0,
            },
            HuyaBitRateModel {
                name: "蓝光".to_string(),
                bit_rate: 2000,
            },
            HuyaBitRateModel {
                name: "4K".to_string(),
                bit_rate: 6000,
            },
            HuyaBitRateModel {
                name: "高清".to_string(),
                bit_rate: 4000,
            },
        ]);
        let qualities = fetch_qualities(&site(), &detail).expect("清晰度");
        let names: Vec<&str> = qualities.iter().map(|q| q.quality.as_str()).collect();
        assert_eq!(names, vec!["原画", "蓝光", "高清"], "4K 被跳过且顺序保留");
        assert_eq!(qualities[0].sort, 0, "sort 为原始下标");
        assert_eq!(qualities[2].sort, 3, "跳过后 sort 不重排");
    }

    #[test]
    fn empty_bitrates_fall_back_to_two_defaults() {
        let detail = detail_with(vec![]);
        let qualities = fetch_qualities(&site(), &detail).expect("清晰度");
        let names: Vec<&str> = qualities.iter().map(|q| q.quality.as_str()).collect();
        assert_eq!(names, vec!["原画", "高清"]);
    }

    #[test]
    fn quality_data_carries_lines_and_bitrate() {
        let mut data = HuyaUrlDataModel::from_json(
            detail_with(vec![HuyaBitRateModel {
                name: "蓝光".to_string(),
                bit_rate: 2000,
            }])
            .data
            .as_deref()
            .expect("data"),
        )
        .expect("解析");
        data.lines = vec![super::super::models::HuyaLineModel {
            line: "https://cdn/flv".to_string(),
            cdn_type: "1".to_string(),
            flv_anti_code: "fa".to_string(),
            hls_anti_code: "ha".to_string(),
            stream_name: "s1".to_string(),
            line_type: super::super::models::HuyaLineType::Flv,
            bit_rate: 0,
            presenter_uid: 1,
        }];
        let detail = detail_with(vec![]);
        let detail = LiveRoomDetail {
            data: Some(data.to_json().expect("序列化")),
            ..detail
        };

        let qualities = fetch_qualities(&site(), &detail).expect("清晰度");
        let parsed = HuyaQualityData::from_json(&qualities[0].data).expect("清晰度数据");
        assert_eq!(parsed.bit_rate, 2000);
        assert_eq!(parsed.urls.len(), 1);
        assert_eq!(parsed.urls[0].stream_name, "s1");
    }

    #[test]
    fn missing_detail_data_is_decode_error() {
        let detail = LiveRoomDetail {
            data: None,
            ..detail_with(vec![])
        };
        let err = fetch_qualities(&site(), &detail).expect_err("缺数据");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn malformed_detail_data_is_decode_error() {
        let detail = LiveRoomDetail {
            data: Some("{oops".to_string()),
            ..detail_with(vec![])
        };
        let err = fetch_qualities(&site(), &detail).expect_err("非法 JSON");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }
}