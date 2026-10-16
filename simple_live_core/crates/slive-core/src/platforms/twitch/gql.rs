//! Twitch GQL 请求构造（对照 `twitch_site.dart:49-64` `buildPersistedRequest`）。
//!
//! Twitch Web 的 GQL 走 **persisted query**：只传 `operationName` + `sha256Hash`，
//! 服务端用哈希取已注册的服务端文档。因此本模块只负责**忠实构造 JSON**，
//! 不做任何签名/加密（Dart 侧亦无）。
//!
//! 键序与 Dart 的模板串一致（`operationName` -> `extensions` -> `variables`），
//! 便于 golden 断言与抓包比对。

use serde_json::{json, Value};

/// 构造单条 persisted query 的请求体（`buildPersistedRequest` 的 Rust 等价物）。
///
/// `variables` 会被原样嵌入；调用方负责其形状（各 operation 不同，见 [`super::detail`] / [`super::play`]）。
pub fn build_persisted_request(operation_name: &str, sha256_hash: &str, variables: Value) -> Value {
    json!({
        "operationName": operation_name,
        "extensions": {
            "persistedQuery": {
                "version": 1,
                "sha256Hash": sha256_hash,
            }
        },
        "variables": variables,
    })
}

/// 批量请求体：`[q1, q2]`（对齐 `twitch_site.dart:263` 的 `[${queries.join(',')}]`）。
///
/// Dart 用字符串拼接；Rust 侧用 `serde_json` 组合，**键序由 `json!` 保证**，
/// 避免手写转义引入的注入面。
pub fn build_batch(queries: &[Value]) -> Value {
    Value::Array(queries.to_vec())
}

/// `ChannelShell` 的 persisted query 哈希（`twitch_site.dart:249`）。
pub const CHANNEL_SHELL_HASH: &str =
    "fea4573a7bf2644f5b3f2cbbdcbee0d17312e48d2e55f080589d053aad353f11";
/// `StreamMetadata` 的 persisted query 哈希（`twitch_site.dart:256`）。
pub const STREAM_METADATA_HASH: &str =
    "b57f9b910f8cd1a4659d894fe7550ccc81ec9052c01e438b290fd66a040b9b93";
/// `PlaybackAccessToken` 的 persisted query 哈希（`twitch_site.dart:94`）。
pub const PLAYBACK_ACCESS_TOKEN_HASH: &str =
    "ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9";

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn persisted_request_matches_dart_shape() {
        let got = build_persisted_request("ChannelShell", CHANNEL_SHELL_HASH, json!({"login": "x"}));
        assert_eq!(
            serde_json::to_string(&got).expect("序列化"),
            r#"{"operationName":"ChannelShell","extensions":{"persistedQuery":{"version":1,"sha256Hash":"fea4573a7bf2644f5b3f2cbbdcbee0d17312e48d2e55f080589d053aad353f11"}},"variables":{"login":"x"}}"#
        );
    }

    #[test]
    fn batch_wraps_queries_in_array() {
        let batch = build_batch(&[
            build_persisted_request("A", "ha", json!({})),
            build_persisted_request("B", "hb", json!({"k": 1})),
        ]);
        let arr = batch.as_array().expect("应为数组");
        assert_eq!(arr.len(), 2);
        assert_eq!(arr[0]["operationName"], "A");
        assert_eq!(arr[1]["variables"]["k"], 1);
    }
}
