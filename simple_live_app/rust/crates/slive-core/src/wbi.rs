//! wbi 签名算法（F-22，纯计算，对照 `bilibili_site.dart:418-534`）。
//!
//! 与本模块区分：网络拉取 + 句柄级缓存（`getWbiKeys` / `getAccessId`）在
//! `platforms::bilibili::wbi`；本模块只保留**确定性算法**（mixinKey 表 + `w_rid` 计算），
//! 便于 golden 断言（AC-21：固定 `img_key/sub_key/wts` -> 固定 `w_rid`）。

use md5::{Digest, Md5};

/// 64 位字符重排表（对齐 Dart `BiliBiliSite.mixinKeyEncTab`）。
pub const MIXIN_KEY_ENC_TAB: [usize; 64] = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29,
    28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25,
    54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
];

/// wbi 签名中需从**参数值**里过滤掉的字符（对齐 Dart）。
pub const FILTERED_CHARS: &str = "!'()*";

/// 对 `img_key + sub_key` 做字符重排，取前 32 位（对齐 Dart `getMixinKey`）。
pub fn get_mixin_key(origin: &str) -> String {
    let bytes = origin.as_bytes();
    MIXIN_KEY_ENC_TAB
        .iter()
        .take(32)
        .map(|&i| bytes.get(i).copied().unwrap_or(b' ') as char)
        .collect()
}

/// 过滤参数值中的 `!'()*`（对齐 Dart `getWbiSign`）。
pub fn filter_value(value: &str) -> String {
    value
        .chars()
        .filter(|c| !FILTERED_CHARS.contains(*c))
        .collect()
}

/// 构造待签名 query：按键排序，`key=encodeQueryComponent(filter_value)` 以 `&` 连接。
pub fn build_signing_query(params: &[(String, String)]) -> String {
    let mut sorted: Vec<&(String, String)> = params.iter().collect();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    sorted
        .into_iter()
        .map(|(key, value)| {
            format!(
                "{key}={}",
                crate::util::encode_query_component(&filter_value(value))
            )
        })
        .collect::<Vec<_>>()
        .join("&")
}

/// 计算 `w_rid = md5(query + mixinKey)`（十六进制小写）。
pub fn get_wbi_sign(params: &[(String, String)], mixin_key: &str) -> String {
    let query = build_signing_query(params);
    let mut hasher = Md5::new();
    hasher.update(format!("{query}{mixin_key}").as_bytes());
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mixin_key_matches_golden() {
        let origin = "7cd084941338484aae1ad9425b84077c4932caff0ff746eab6f01bf08b70ac45";
        assert_eq!(get_mixin_key(origin), "ea1db124af3c7062474693fa704f4ff8");
    }

    #[test]
    fn wbi_sign_matches_golden() {
        let params = vec![
            ("room_id".to_string(), "6".to_string()),
            ("wts".to_string(), "1700000000".to_string()),
        ];
        let mixin = get_mixin_key(
            "7cd084941338484aae1ad9425b84077c4932caff0ff746eab6f01bf08b70ac45",
        );
        assert_eq!(
            build_signing_query(&params),
            "room_id=6&wts=1700000000",
            "签名 query 顺序/编码须与 golden 一致"
        );
        assert_eq!(
            get_wbi_sign(&params, &mixin),
            "46e0afca2af785f6dbdc24935d856d79"
        );
    }
}
