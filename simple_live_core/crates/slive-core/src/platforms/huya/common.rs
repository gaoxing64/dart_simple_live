//! 虎牙请求常量与请求头（对照 Dart `common/huya_request_params.dart`）。
//!
//! 纪律：URL / 正则 / UA 全部是协议常量，**只在本模块定义**；
//! `HYSDK_UA` 在 Dart 是可变的 `static`（被 `setSiteAttrs` 改写），
//! Rust 侧落为**句柄级**状态（`HuyaSite::hysdk_ua`，见 `site.rs`），
//! 请求集合与 Dart 完全一致（迁句柄级属行为不变，见 `13-spec.md §10` 进程级缓存条目）。

/// 站点主域（房间页 / 列表页）。
pub const BASE_URL: &str = "https://www.huya.com";
/// TUP 网关（`getCdnTokenInfoEx` / `getHeadLineMessageBoard`）。
pub const WUP_URL: &str = "http://wup.huya.com";
/// TUP 请求路径（`liveui` / `wupui` 两个 servant 共用空路径）。
pub const WUP_PATH: &str = "/";
/// 匿名登录使用的浏览器 UA（对齐 Dart `kUserAgent`）。
pub const K_USER_AGENT: &str = "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36 Edg/117.0.0.0";
/// 虎牙 PC 端 SDK UA 默认值（可被 `setSiteAttrs` 覆盖）。
pub const DEFAULT_HYSDK_UA: &str =
    "HYSDK(Windows,30000002)_APP(pc_exe&7100004&official)_SDK(trans&2.40.0.6448)";

/// 匹配房间页内嵌的 `TT_ROOM_DATA`（对齐 Dart `ROOM_DATA_REGEX`）。
pub const ROOM_DATA_REGEX: &str = r"var\s+TT_ROOM_DATA\s*=\s*(\{[\s\S]*?\})";
/// 匹配房间页内嵌的 `stream:` 块（对齐 Dart `STREAM_REGEX`）。
pub const STREAM_REGEX: &str = r"stream:\s*(\{[\s\S]*?\n\s*\})";
/// 匹配 YY 号（对齐 Dart `AYYUID_REGEX`；当前无调用方，保留常量供后续使用）。
pub const AYYUID_REGEX: &str = r#""yyid":"?(\d+)"?"#;

/// 子分类接口。
pub const SUB_CATEGORY_URL: &str = "https://live.cdn.huya.com/liveconfig/game/bussLive";
/// 房间列表接口（分类下房间 + 推荐共用）。
pub const ROOM_LIST_URL: &str = "https://www.huya.com/cache.php";
/// 搜索接口（房间 / 主播共用）。
pub const SEARCH_URL: &str = "https://search.cdn.huya.com/";
/// 弹幕 WS 服务端。
pub const WS_SERVER_URL: &str = "wss://cdnws.api.huya.com:443";

/// 标准请求头（Origin / Referer / User-Agent），对齐 Dart `requestHeaders`。
pub fn request_headers(hysdk_ua: &str) -> Vec<(String, String)> {
    vec![
        ("Origin".to_string(), BASE_URL.to_string()),
        ("Referer".to_string(), BASE_URL.to_string()),
        ("User-Agent".to_string(), hysdk_ua.to_string()),
    ]
}

/// 随机生成虎牙 SDK 的 UA（如 `adr&13.1.0.3456&official&31`）。
///
/// 对齐 Dart `HuyaRequestParams.requestHuyaUA`：四平台随机 + 部分平台追加随机子版本 +
/// 部分平台追加 Android API Level（28-36）。随机源不可注入（Dart 亦然），仅用于
/// 请求头伪装，不参与任何签名/计算，故不要求确定性。
pub fn random_huya_ua() -> String {
    // (name, version, has_api_level, has_sub_version)
    const PLATFORMS: [(&str, &str, bool, bool); 4] = [
        ("adr", "13.1.0", true, true),
        ("ios", "13.1.0", false, false),
        ("huya_nftv", "2.6.10", true, true),
        ("pc_exe", "7000000", false, false),
    ];
    let (name, base_version, has_api_level, has_sub_version) =
        PLATFORMS[random_below(PLATFORMS.len() as u64) as usize];

    let mut version = base_version.to_string();
    if has_sub_version {
        version = format!("{version}.{}", random_below(2000) + 3000);
    }
    let mut ua = format!("{name}&{version}&official");
    if has_api_level {
        ua = format!("{ua}&{}", random_below(9) + 28);
    }
    ua
}

/// 取 `[0, n)` 的随机整数（`n == 0` 返回 0）。
fn random_below(n: u64) -> u64 {
    if n == 0 {
        return 0;
    }
    super::utils::random_u64() % n
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn headers_carry_origin_referer_and_sdk_ua() {
        let headers = request_headers(DEFAULT_HYSDK_UA);
        assert_eq!(headers.len(), 3);
        assert_eq!(headers[0], ("Origin".to_string(), BASE_URL.to_string()));
        assert_eq!(headers[1], ("Referer".to_string(), BASE_URL.to_string()));
        assert_eq!(headers[2].1, DEFAULT_HYSDK_UA);
    }

    #[test]
    fn random_ua_matches_platform_shapes() {
        for _ in 0..40 {
            let ua = random_huya_ua();
            let parts: Vec<&str> = ua.split('&').collect();
            match parts[0] {
                "adr" => {
                    assert_eq!(parts.len(), 4, "adr 应为 name&version.x.y&official&apiLevel");
                    assert!(parts[1].starts_with("13.1.0."));
                    assert_eq!(parts[2], "official");
                    assert!(parts[3].parse::<u32>().is_ok_and(|v| (28..=36).contains(&v)));
                }
                "ios" => {
                    assert_eq!(parts.len(), 3, "ios 无 apiLevel");
                    assert_eq!(parts[1], "13.1.0");
                }
                "huya_nftv" => {
                    assert_eq!(parts.len(), 4, "huya_nftv 有 apiLevel 且版本带子号");
                    assert!(parts[1].starts_with("2.6.10."));
                }
                "pc_exe" => {
                    assert_eq!(parts.len(), 3, "pc_exe 无 apiLevel 且无子版本");
                    assert_eq!(parts[1], "7000000");
                }
                other => panic!("未知平台 {other}"),
            }
        }
    }
}