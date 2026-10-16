//! 虎牙详情/取流数据模型（对照 `huya_site.dart:585-665` 的三个 Dart 模型）。
//!
//! 与 B站的差异：虎牙 `LiveRoomDetail.data` 承载 `HuyaUrlDataModel`（含线路与清晰度），
//! `LivePlayQuality.data` 承载 `{urls, bitRate}`。两者在 core 层都是 **JSON String**
//! （`LiveRoomDetail.data` / `LivePlayQuality.data` 字段类型为 `String`），
//! 序列化键名用 snake_case 且**顺序稳定**（便于往返断言）。
//!
//! 纪律：解析失败 -> [`SliveError::Decode`]（J-5：非法 JSON 抛类型化错误，不静默兜底）。

use serde::{Deserialize, Serialize};

use crate::error::SliveError;

/// 线路协议类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HuyaLineType {
    /// FLV（直连流）。
    Flv,
    /// HLS（m3u8）。
    Hls,
}

impl HuyaLineType {
    /// 是否为 HLS。
    pub fn is_hls(self) -> bool {
        matches!(self, Self::Hls)
    }
}

/// 单条线路（对照 Dart `HuyaLineModel`）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HuyaLineModel {
    /// 线路前缀（如 `https://cdn...`）。
    pub line: String,
    /// CDN 类型。
    pub cdn_type: String,
    /// FLV anticode（本实现不消费 —— 取流统一走 TARS token，见 `anti_code`）。
    pub flv_anti_code: String,
    /// HLS anticode（同上）。
    pub hls_anti_code: String,
    /// 流名。
    pub stream_name: String,
    /// 线路协议。
    pub line_type: HuyaLineType,
    /// 该线路的码率（0 表示原画；字段保留以对齐 Dart）。
    pub bit_rate: i32,
    /// 主播 uid（取流签名用）。
    pub presenter_uid: i64,
}

/// 清晰度项（对照 Dart `HuyaBitRateModel`）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HuyaBitRateModel {
    /// 清晰度名（如 `原画` / `蓝光`）。
    pub name: String,
    /// 码率（0 = 原画；>0 时作为 `ratio` 参数）。
    pub bit_rate: i32,
}

/// `LiveRoomDetail.data` 的载荷（对照 Dart `HuyaUrlDataModel`）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HuyaUrlDataModel {
    /// Dart 侧固定占位串（`"huya need rebuild new url"`），保留以对齐 JSON 形状。
    pub url: String,
    /// 占位 uid（Dart 用 `getUid(t: 13, e: 10)` 生成，无读取方）。
    pub uid: String,
    /// 可用线路。
    pub lines: Vec<HuyaLineModel>,
    /// 可用清晰度。
    pub bit_rates: Vec<HuyaBitRateModel>,
}

impl HuyaUrlDataModel {
    /// 序列化进 `LiveRoomDetail.data`。
    pub fn to_json(&self) -> Result<String, SliveError> {
        serde_json::to_string(self)
            .map_err(|e| SliveError::decode(format!("序列化虎牙取流数据失败: {e}")))
    }

    /// 从 `LiveRoomDetail.data` 解析。
    pub fn from_json(json: &str) -> Result<Self, SliveError> {
        serde_json::from_str(json)
            .map_err(|e| SliveError::decode(format!("解析虎牙取流数据失败: {e}")))
    }
}

/// `LivePlayQuality.data` 的载荷：`{urls, bit_rate}`（对齐 Dart 的 `{urls, bitRate}`）。
///
/// Dart 的 `urls` 是 `List<HuyaLineModel>`；此处为同一结构的 JSON 数组。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HuyaQualityData {
    /// 参与取流的线路集合。
    pub urls: Vec<HuyaLineModel>,
    /// 码率（0 = 原画；消费时作为 `ratio` 追加）。
    pub bit_rate: i32,
}

impl HuyaQualityData {
    /// 序列化进 `LivePlayQuality.data`。
    pub fn to_json(&self) -> Result<String, SliveError> {
        serde_json::to_string(self)
            .map_err(|e| SliveError::decode(format!("序列化虎牙清晰度数据失败: {e}")))
    }

    /// 从 `LivePlayQuality.data` 解析。
    pub fn from_json(json: &str) -> Result<Self, SliveError> {
        serde_json::from_str(json)
            .map_err(|e| SliveError::decode(format!("解析虎牙清晰度数据失败: {e}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_line() -> HuyaLineModel {
        HuyaLineModel {
            line: "https://cdn.example/live".to_string(),
            cdn_type: "1".to_string(),
            flv_anti_code: "flv-code".to_string(),
            hls_anti_code: "hls-code".to_string(),
            stream_name: "stream1".to_string(),
            line_type: HuyaLineType::Flv,
            bit_rate: 0,
            presenter_uid: 123,
        }
    }

    fn sample_url_data() -> HuyaUrlDataModel {
        HuyaUrlDataModel {
            url: "huya need rebuild new url".to_string(),
            uid: "0123456789012".to_string(),
            lines: vec![sample_line()],
            bit_rates: vec![
                HuyaBitRateModel {
                    name: "原画".to_string(),
                    bit_rate: 0,
                },
                HuyaBitRateModel {
                    name: "高清".to_string(),
                    bit_rate: 2000,
                },
            ],
        }
    }

    #[test]
    fn url_data_roundtrips_with_stable_key_order() {
        let data = sample_url_data();
        let json = data.to_json().expect("序列化");
        assert_eq!(
            json,
            r#"{"url":"huya need rebuild new url","uid":"0123456789012","lines":[{"line":"https://cdn.example/live","cdn_type":"1","flv_anti_code":"flv-code","hls_anti_code":"hls-code","stream_name":"stream1","line_type":"flv","bit_rate":0,"presenter_uid":123}],"bit_rates":[{"name":"原画","bit_rate":0},{"name":"高清","bit_rate":2000}]}"#
        );
        assert_eq!(HuyaUrlDataModel::from_json(&json).expect("反序列化"), data);
    }

    #[test]
    fn quality_data_roundtrips() {
        let quality = HuyaQualityData {
            urls: vec![sample_line()],
            bit_rate: 2000,
        };
        let json = quality.to_json().expect("序列化");
        assert!(json.contains(r#""bit_rate":2000"#));
        assert_eq!(HuyaQualityData::from_json(&json).expect("反序列化"), quality);
    }

    #[test]
    fn invalid_json_is_decode_error() {
        let err = HuyaUrlDataModel::from_json("not json").expect_err("非法 JSON");
        assert!(matches!(err, SliveError::Decode(_)), "实际 {err:?}");
    }

    #[test]
    fn line_type_reports_hls_flag() {
        assert!(!HuyaLineType::Flv.is_hls());
        assert!(HuyaLineType::Hls.is_hls());
    }
}