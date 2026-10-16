//! 反 anticode（取流 URL 拼装的核心纯计算，对照 `huya_site.dart:348-397` `buildAntiCode`）。
//!
//! 虎牙取流地址的签名参数由三部分决定：
//! 1. 页面下发的 `flvAntiCode`（query 串，含 `fm` / `wsTime` / `fs` / `t` / `ctype`）；
//! 2. `presenterUid`（房间 topSid）；
//! 3. `getCdnTokenInfoEx` 返回的 `sFlvToken`（服务端签发，本模块只消费）。
//!
//! 算法（Python/Dart 双向对齐，勿改顺序）：
//! `seqId = presenterUid + nowMs` → `secretHash = md5("{seqId}|{ctype}|{platformId}")`
//! → `wsSecret = md5("{secretPrefix}_{calcUid}_{stream}_{secretHash}_{wsTime}")`。
//!
//! 纪律：本模块**不做 I/O**、不记日志（签名中间值含 `fm`，属半凭证，见 AC-40）。

use super::utils::{md5_hex, percent_decode, random_below, rotl64, base64_decode};

/// WAP 端平台 id（`t=103` 时 `calcUid` 不做 `rotl64`，且额外带 `uid`/`uuid`）。
const WAP_PLATFORM_ID: i64 = 103;
/// `ctype` 缺省值。
/// `ctype` 缺省值（`pub`：测试与诊断需要引用同一常量）。
pub const DEFAULT_CTYPE: &str = "huya_pc_exe";

/// 反 anticode 的输入（`sFlvToken` 即页面 `fm` 的载体，query 串形态）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AntiCodeParts {
    /// `ctype`（缺省 `huya_pc_exe`）。
    pub ctype: String,
    /// 平台 id `t`（缺省 0）。
    pub platform_id: i64,
    /// `fm`（base64 编码的 secret 前缀载体，**未**百分号解码）。
    pub fm: String,
    /// `fs`。
    pub fs: String,
    /// `wsTime`（十六进制字符串，原样参与运算）。
    pub ws_time: String,
}

/// 解析 `sFlvToken`（页面 anticode query 串）。
///
/// **缺 `fm` 时返回 `None`** —— 对齐 Dart `buildAntiCode`：
/// `if (!mapAnti.containsKey("fm")) return antiCode;`（原样透传，不做签名）。
/// 缺 `wsTime` / `fs` 时 Dart 会抛（`mapAnti['wsTime']!`）→ Rust 返回 `Err`。
pub fn parse_anti_code(anti_code: &str) -> Result<Option<AntiCodeParts>, String> {
    let pairs = parse_query(anti_code);
    let get = |key: &str| -> Option<String> {
        pairs
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.clone())
            .filter(|v| !v.is_empty())
    };

    let Some(fm) = get("fm") else {
        return Ok(None);
    };
    let ws_time = get("wsTime")
        .ok_or_else(|| format!("anticode 缺少 wsTime 字段: {anti_code}"))?;
    let fs = get("fs")
        .ok_or_else(|| format!("anticode 缺少 fs 字段: {anti_code}"))?;

    Ok(Some(AntiCodeParts {
        ctype: get("ctype").unwrap_or_else(|| DEFAULT_CTYPE.to_string()),
        // Dart: int.tryParse(mapAnti["t"]?.first ?? "0")，解析失败为 null（参与字符串插值时视为 "null"）。
        platform_id: get("t")
            .map(|v| v.trim().parse::<i64>().unwrap_or(-1))
            .unwrap_or(0),
        fm,
        fs,
        ws_time,
    }))
}

/// 由页面 anticode 派生真正的取流签名串（query 串，无前导 `?`）。
///
/// `now_ms` 与随机源**显式传入**，便于 golden 断言（对齐 `TimeSource` 可注入口径）。
/// **无 `fm` 时原样返回输入串**（对齐 Dart `huya_site.dart:351-353`
/// `if (!mapAnti.containsKey("fm")) return antiCode;`）—— 不是 `None`，
/// 调用方拿到的始终是可直接拼进 URL 的 query。
pub fn build_anti_code(
    anti_code: &str,
    stream: &str,
    presenter_uid: i64,
    now_ms: u64,
) -> Result<Option<String>, String> {
    let Some(parts) = parse_anti_code(anti_code)? else {
        return Ok(Some(anti_code.to_string()));
    };

    let is_wap = parts.platform_id == WAP_PLATFORM_ID;
    let seq_id = presenter_uid as u64 + now_ms;
    let platform_id_text = parts.platform_id.to_string();
    let secret_hash = md5_hex(&format!(
        "{seq_id}|{}|{platform_id_text}",
        parts.ctype
    ));

    let convert_uid = rotl64(presenter_uid);
    let calc_uid = if is_wap { presenter_uid } else { convert_uid };

    // Dart: Uri.decodeComponent(fm) -> base64.decode -> utf8 -> split('_').first
    let fm_decoded = percent_decode(&parts.fm);
    let decoded = base64_decode(&fm_decoded)
        .map_err(|e| format!("anticode fm base64 解码失败: {e}"))?;
    let prefix_text = String::from_utf8_lossy(&decoded).into_owned();
    let secret_prefix = prefix_text.split('_').next().unwrap_or_default().to_string();

    let secret_str = format!(
        "{secret_prefix}_{calc_uid}_{stream}_{secret_hash}_{}",
        parts.ws_time
    );
    let ws_secret = md5_hex(&secret_str);

    let mut out: Vec<(String, String)> = vec![
        ("wsSecret".to_string(), ws_secret),
        ("wsTime".to_string(), parts.ws_time.clone()),
        ("seqid".to_string(), seq_id.to_string()),
        ("ctype".to_string(), parts.ctype.clone()),
        ("ver".to_string(), "1".to_string()),
        ("fs".to_string(), parts.fs.clone()),
        ("fm".to_string(), fm_decoded),
        ("t".to_string(), platform_id_text),
    ];
    if is_wap {
        out.push(("uid".to_string(), presenter_uid.to_string()));
        out.push(("uuid".to_string(), wap_uuid(&parts.ws_time)));
    } else {
        out.push(("u".to_string(), convert_uid.to_string()));
    }

    Ok(Some(
        out.iter()
            .map(|(k, v)| format!("{k}={v}"))
            .collect::<Vec<_>>()
            .join("&"),
    ))
}

/// WAP 端附加 uuid（对齐 Dart `getPlayUrl` 中的 `ct` / `uuid` 计算）。
///
/// Dart：`ct = ((wsTime(16进制) + rnd) * 1000).toInt()`，
/// `uuid = (((ct % 1e10) + rnd) * 1e3 % 0xffffffff).toInt()`。
/// 本实现用 `f64` 同序运算以保持一致的取整行为；随机源不可注入（Dart 亦不可）。
fn wap_uuid(ws_time: &str) -> String {
    let ws_time_value = i64::from_str_radix(ws_time, 16).unwrap_or(0) as f64;
    let ct = ((ws_time_value + random_fraction()) * 1000.0) as i64;
    let uuid = (((ct as f64 % 1e10) + random_fraction()) * 1e3 % 4294967295.0) as i64;
    uuid.to_string()
}

/// `[0, 1)` 随机小数（对齐 Dart `Random().nextDouble()`）。
fn random_fraction() -> f64 {
    random_below(1_000_000) as f64 / 1_000_000.0
}

/// 解析 query 串为键值对（保留首次出现，值不做解码 —— 与 Dart `queryParametersAll` 的取值语义一致）。
/// 解析 query 串为键值对（`pub`：集成测试复用同一解析口径）。
pub fn parse_query(query: &str) -> Vec<(String, String)> {
    query
        .split('&')
        .filter(|pair| !pair.is_empty())
        .filter_map(|pair| {
            pair.split_once('=')
                .map(|(k, v)| (k.to_string(), v.to_string()))
        })
        .collect()
}

/// 拼接最终取流地址（对齐 Dart `getPlayUrl`）。
///
/// `suffix` 由线路类型决定（`flv` / `m3u8`）；`bit_rate > 0` 时追加 `ratio`。
pub fn build_play_url(
    line: &str,
    stream_name: &str,
    is_hls: bool,
    anti_code: &str,
    bit_rate: i32,
) -> Result<String, String> {
    let suffix = if is_hls { "m3u8" } else { "flv" };
    let mut url = format!("{line}/{stream_name}.{suffix}?{anti_code}&codec=264");
    if bit_rate > 0 {
        url.push_str(&format!("&ratio={bit_rate}"));
    }
    Ok(url)
}
