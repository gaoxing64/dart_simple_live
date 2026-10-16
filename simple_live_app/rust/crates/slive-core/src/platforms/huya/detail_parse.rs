//! F-06 房间页内嵌数据的解析纯函数（对照 `huya_site.dart:225-342` 的正则与字段口径）。
//!
//! 与 [`super::detail`]（IO 编排）分离：本模块**只做解析**，不发请求，便于离线夹具断言。
//!
//! 关键口径（勿"顺手修正"）：
//! - 两条正则（`TT_ROOM_DATA` / `stream:`）的匹配方式与 Dart 一致；
//! - `stream:` 块取**整段匹配**去掉前缀后取首行（丢弃行尾残渣），与 Dart 的
//!   `replaceAll("stream: ", "").split('\n')[0]` 等价；
//! - 线路按「每条流信息内 FLV 在前、HLS 在后」产出（对齐 Dart 的 `lineTypes.forEach`）。

use once_cell::sync::Lazy;
use regex::Regex;
use serde_json::Value;

use crate::error::SliveError;
use crate::util::as_i32;

use super::common::STREAM_REGEX;
use super::models::{HuyaBitRateModel, HuyaLineModel, HuyaLineType};

static STREAM: Lazy<Regex> =
    Lazy::new(|| Regex::new(STREAM_REGEX).expect("流数据正则字面量合法"));

/// 抽取 `stream:` 块的 JSON 文本。
///
/// Dart：`RegExp(STREAM_REGEX).firstMatch(...)?.group(0)?.replaceAll("stream: ", "").split('\n')[0] ?? '""'`
/// —— 取整个匹配（而非捕获组）并去掉前缀，故内层 `}` 之后到行尾的残渣会被丢弃。
/// 这里等价实现：整段匹配去掉前缀后取首行；首行非 JSON 时返回错误。
pub(crate) fn extract_stream(page: &str) -> Result<String, SliveError> {
    let Some(matched) = STREAM.find(page) else {
        return Err(SliveError::decode("房间页未内嵌 stream 数据"));
    };
    let stripped = matched.as_str().replacen("stream:", "", 1);
    let first_line = stripped.lines().next().unwrap_or_default().trim().to_string();
    if first_line.is_empty() {
        return Err(SliveError::decode("stream 数据为空"));
    }
    Ok(first_line)
}

/// 解析可用线路：`gameStreamInfoList[*]` 的 `sFlvUrl` / `sHlsUrl`（非空才产出）。
///
/// 对齐 Dart：`lineTypes.forEach` 先 FLV 后 HLS，故每条流信息内 FLV 在前。
pub(crate) fn parse_lines(stream_data: &Value, presenter_uid: i64) -> Vec<HuyaLineModel> {
    let mut lines = Vec::new();
    for item in crate::util::array_at(stream_data, "/data/0/gameStreamInfoList") {
        let stream_name = text(item, "sStreamName");
        let flv_anti_code = text(item, "sFlvAntiCode");
        let hls_anti_code = text(item, "sHlsAntiCode");
        let cdn_type = text(item, "sCdnType");
        for (key, line_type) in [
            ("sFlvUrl", HuyaLineType::Flv),
            ("sHlsUrl", HuyaLineType::Hls),
        ] {
            let line = text(item, key);
            if line.is_empty() {
                continue;
            }
            lines.push(HuyaLineModel {
                line,
                cdn_type: cdn_type.clone(),
                flv_anti_code: flv_anti_code.clone(),
                hls_anti_code: hls_anti_code.clone(),
                stream_name: stream_name.clone(),
                line_type,
                bit_rate: 0,
                presenter_uid,
            });
        }
    }
    lines
}

/// 解析清晰度：`vMultiStreamInfo[*]`，跳过 HDR（对齐 Dart `name.contains("HDR")`）。
pub(crate) fn parse_bit_rates(stream_data: &Value) -> Vec<HuyaBitRateModel> {
    crate::util::array_at(stream_data, "/vMultiStreamInfo")
        .iter()
        .map(|item| HuyaBitRateModel {
            name: text(item, "sDisplayName"),
            bit_rate: as_i32(item.get("iBitRate")).unwrap_or(0),
        })
        .filter(|rate| !rate.name.contains("HDR"))
        .collect()
}

pub(crate) fn text(item: &Value, key: &str) -> String {
    item.get(key)
        .map(crate::util::value_to_string)
        .unwrap_or_default()
}