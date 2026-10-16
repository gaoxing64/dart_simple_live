//! cookie 解析（对照 Dart `common/parse_cookie.dart:4-12`）。

use std::collections::HashMap;

/// 解析 cookie 串为键值映射（按 `;` 切分，按首个 `=` 拆键值，均 trim）。
pub(crate) fn parse_cookie(raw: &str) -> HashMap<String, String> {
    raw.split(';')
        .map(str::trim)
        .filter(|part| part.contains('='))
        .filter_map(|part| {
            let (key, value) = part.split_once('=')?;
            Some((key.trim().to_string(), value.trim().to_string()))
        })
        .collect()
}

/// 取指定 cookie 键（缺失 -> `None`）。
pub(crate) fn find_cookie(raw: &str, key: &str) -> Option<String> {
    parse_cookie(raw).remove(key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_pairs_and_skips_invalid() {
        let map = parse_cookie("SESSDATA=abc; buvid3=BUV3; novalue");
        assert_eq!(map.get("SESSDATA").map(String::as_str), Some("abc"));
        assert_eq!(map.get("buvid3").map(String::as_str), Some("BUV3"));
        assert!(!map.contains_key("novalue"));
    }

    #[test]
    fn find_cookie_returns_value() {
        assert_eq!(
            find_cookie("buvid3=X;buvid4=Y;", "buvid4"),
            Some("Y".to_string())
        );
        assert_eq!(find_cookie("buvid3=X;", "missing"), None);
    }
}
