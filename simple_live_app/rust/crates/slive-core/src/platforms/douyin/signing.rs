//! a_bogus 签名调用点（本文件是 core 侧**唯一**引用 `signature` 子模块的地方）。
//!
//! 为什么单独一层：签名算法（SM3 / RC4 / 字节变换 / 双字母表）在
//! `signature/` 子模块里，本文件只负责「拼 query -> 调签名 -> 拼回 URL」，
//! 于是协议组装与密码学实现解耦，签名实现可独立做确定性 golden 测试。
//!
//! 对照 Dart `DouyinUtils.buildRequestUrl`（`douyin_utils.dart:22-42`）：
//! ```dart
//! exParams['aid'] = '6383'; exParams['compress'] = 'gzip';
//! exParams['device_platform'] = 'web'; exParams['browser_language'] = 'zh-CN';
//! exParams['browser_platform'] = 'Win32'; exParams['browser_name'] = 'Edge';
//! exParams['browser_version'] = '125.0.0.0';
//! if (!exParams.containsKey('msToken')) exParams['msToken'] = getMSToken();
//! final signed = abogus.generateAbogus(Uri(queryParameters: exParams).query, body: '').first;
//! ```
//!
//! ⚠️ 三处顺序敏感点（改动会直接导致签名被拒）：
//! 1. `exParams` 是 Dart `Map` 的**插入序**（上面 7 个键是**后追加**的，
//!    与调用方自己传的键一起决定最终 query 串）；
//! 2. `msToken` 只在**缺失时**才追加（重复追加会多一个键）；
//! 3. 签名前先做 query 编码（空格 -> `+`），签名对象是**编码后**的串。

use crate::error::SliveError;

use super::danmaku::args::DEFAULT_USER_AGENT;
use super::signature;
use super::util::{ms_token, QueryParams, MS_TOKEN_LENGTH};

/// `buildRequestUrl` 追加的固定 7 个键（值即 Dart 里的字面量）。
///
/// ⚠️ **`aid=6383` 是硬约束**：缺它服务端直接 400 空 body（2026-10-16 真机复现，
/// 用户首页推荐流报 `CoreError` 即由此而来 —— 而离线夹具对此**完全无感知**，
/// 因为夹具只校验响应解析、不校验请求参数）。故由
/// `common_params_include_the_mandatory_seven` 逐个钉住。
fn append_common_params(params: &mut QueryParams) {
    params.put("aid", "6383");
    params.put("compress", "gzip");
    params.put("device_platform", "web");
    params.put("browser_language", "zh-CN");
    params.put("browser_platform", "Win32");
    params.put("browser_name", "Edge");
    params.put("browser_version", "125.0.0.0");
}

/// 为 HTTP 读链路构造**完整已签名 URL**（`base_url?{signed_query}`）。
///
/// `params` 是调用方自己的业务参数（插入序会被保留）；函数在其后追加 Dart 的
/// 固定 7 键与 `msToken`，再对编码后的 query 串做 a_bogus 签名。
pub fn build_signed_url(base_url: &str, params: &QueryParams) -> Result<String, SliveError> {
    let mut merged = params.clone();
    append_common_params(&mut merged);
    if !merged.contains("msToken") {
        merged.put("msToken", ms_token(MS_TOKEN_LENGTH));
    }
    let query = merged.to_query();
    let signed = signature::a_bogus(&query, DEFAULT_USER_AGENT);
    if base_url.contains('?') {
        return Err(SliveError::invalid_input(format!(
            "base_url 不应自带 query（签名需覆盖完整 query 串）: {base_url}"
        )));
    }
    Ok(format!("{base_url}?{signed}"))
}

/// 为 WS 握手构造签名（`generateXBogus(md5(固定顺序参数串), 1)`）。
///
/// 对照 Dart `DouyinDanmaku.getSignature`（`douyin_danmaku.dart:210-238`）：
/// 13 个键的**固定顺序**拼成 `k=v,k=v,...` -> md5 hex -> `generateXBogus(md5, 1)`。
/// 参数缺失一律按空串参与（Dart 用 `map[key] ?? ''` 的等价口径）。
pub fn build_ws_signature(
    room_id: &str,
    user_unique_id: &str,
    version_code: &str,
    sdk_version: &str,
) -> Result<String, SliveError> {
    let pairs: [(&str, &str); 13] = [
        ("live_id", "1"),
        ("aid", "6383"),
        ("version_code", version_code),
        ("webcast_sdk_version", sdk_version),
        ("room_id", room_id),
        ("sub_room_id", ""),
        ("sub_channel_id", ""),
        ("did_rule", "3"),
        ("user_unique_id", user_unique_id),
        ("device_platform", "web"),
        ("device_type", ""),
        ("ac", ""),
        ("identity", "audience"),
    ];
    let raw = pairs
        .iter()
        .map(|(k, v)| format!("{k}={v}"))
        .collect::<Vec<_>>()
        .join(",");
    let md5_hex = md5_hex(raw.as_bytes());
    signature::x_bogus(&md5_hex, 1)
}

/// 小写十六进制 md5（对齐 Dart `md5.convert(...).toString()`）。
fn md5_hex(data: &[u8]) -> String {
    use md5::{Digest, Md5};
    let mut hasher = Md5::new();
    hasher.update(data);
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn md5_hex_matches_dart_to_string_form() {
        assert_eq!(
            md5_hex(b""),
            "d41d8cd98f00b204e9800998ecf8427e",
            "空串 md5 必须与 Dart 一致"
        );
        assert_eq!(
            md5_hex(b"abc"),
            "900150983cd24fb0d6963f7d28e17f72",
            "abc 的 md5 是标准向量"
        );
    }

    #[test]
    fn common_params_include_the_mandatory_seven() {
        // 这是「漏参数」缺陷的**总闸**：任何走 buildRequestUrl 的接口都会经过这里。
        // 逐个钉住 Dart `buildRequestUrl` 追加的 7 个键 —— 少一个就可能 400。
        let mut q = QueryParams::new();
        q.put("app_name", "douyin_web");
        append_common_params(&mut q);
        let map: std::collections::HashMap<_, _> = q.iter().collect();
        let expected = [
            ("aid", "6383"),
            ("compress", "gzip"),
            ("device_platform", "web"),
            ("browser_language", "zh-CN"),
            ("browser_platform", "Win32"),
            ("browser_name", "Edge"),
            ("browser_version", "125.0.0.0"),
        ];
        for (key, value) in expected {
            assert_eq!(map[key], value, "公共参数缺 {key} 或值不符");
        }
        assert_eq!(q.iter().count(), 8, "业务 1 键 + 公共 7 键，不应多出其它键");
        // 调用方参数在前（顺序参与 a_bogus 签名）
        assert_eq!(q.iter().next().map(|(k, _)| k), Some("app_name"));
    }

    #[test]
    fn build_signed_url_appends_fixed_params_and_a_bogus() {
        let mut params = QueryParams::new();
        params.put("app_name", "douyin_web").put("web_rid", "416144012050");
        let url = build_signed_url("https://live.douyin.com/webcast/room/web/enter/", &params)
            .expect("应能构造");
        assert!(url.starts_with("https://live.douyin.com/webcast/room/web/enter/?"));
        assert!(url.contains("app_name=douyin_web"), "业务参数须保留");
        assert!(url.contains("web_rid=416144012050"));
        assert!(url.contains("aid=6383"), "固定参数须追加");
        assert!(url.contains("browser_version=125.0.0.0"));
        assert!(url.contains("msToken="), "缺失时须补 msToken");
        assert!(url.contains("&a_bogus="), "签名参数须挂在末尾");
    }

    #[test]
    fn caller_supplied_ms_token_is_not_duplicated() {
        let mut params = QueryParams::new();
        params.put("msToken", "FIXED-TOKEN");
        let url = build_signed_url("https://x/y", &params).expect("应能构造");
        assert_eq!(url.matches("msToken=").count(), 1, "msToken 不得重复");
        assert!(url.contains("msToken=FIXED-TOKEN"));
    }

    #[test]
    fn signed_url_rejects_base_with_existing_query() {
        let err = build_signed_url("https://x/y?a=1", &QueryParams::new())
            .expect_err("带 query 的 base 应报错");
        assert!(matches!(err, SliveError::InvalidInput(_)), "实际 {err:?}");
    }

    #[test]
    fn ws_signature_is_32_char_hex_input_and_stable_length_output() {
        let sig = build_ws_signature("7382735338101328680", "7273033021933946", "180800", "1.0.14-beta.0")
            .expect("应能签名");
        assert!(!sig.is_empty());
        // Dart 侧参数顺序固定 -> md5 固定 -> 同一 counter 的骨架长度固定（16 字符）
        assert_eq!(sig.chars().count(), 16, "XBogus 编码后固定 16 字符");
    }

    #[test]
    fn ws_signature_varies_with_room_id() {
        let a = build_ws_signature("111", "222", "180800", "1.0.14-beta.0").expect("签名");
        let b = build_ws_signature("112", "222", "180800", "1.0.14-beta.0").expect("签名");
        assert_ne!(a, b, "room_id 变化必须改变签名输入");
    }
}
