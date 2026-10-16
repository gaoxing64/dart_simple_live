//! 斗鱼业务错误码校验（对齐斗鱼接口的 `error` 字段口径）。
//!
//! 与 B站不同：斗鱼 Web/M 端接口用 **`error`**（不是 `code`）表示业务错误。
//! 团队错误口径（`13-spec.md` §9 / IP-3 约束）：业务码非 0 一律抛
//! [`SliveError::Api`]，**不自动重试**。
//!
//! `msg` 缺失时回落到 `data`（斗鱼部分接口把原因放在 `data` 里），再回落到空串。

use serde_json::Value;

use crate::error::SliveError;
use crate::util::value_to_string;

/// `error != 0` -> [`SliveError::Api`]；无 `error` 键或为 `0` -> 通过。
pub(crate) fn check_error_code(value: &Value) -> Result<(), SliveError> {
    let Some(code) = value.get("error").and_then(Value::as_i64) else {
        return Ok(());
    };
    if code == 0 {
        return Ok(());
    }
    let message = value
        .get("msg")
        .or_else(|| value.get("message"))
        .or_else(|| value.get("data"))
        .map(value_to_string)
        .unwrap_or_default();
    Err(SliveError::Api {
        code: code as i32,
        message,
    })
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn passes_zero_and_missing_key() {
        assert!(check_error_code(&json!({"error": 0})).is_ok());
        assert!(check_error_code(&json!({"data": []})).is_ok());
    }

    #[test]
    fn nonzero_becomes_api_error_with_message_fallbacks() {
        let err = check_error_code(&json!({"error": -1, "msg": "风控"}))
            .expect_err("error!=0 必须抛错");
        assert!(matches!(
            err,
            SliveError::Api {
                code: -1,
                message
            } if message == "风控"
        ));

        let fallback = check_error_code(&json!({"error": 100, "data": "房间已封禁"}))
            .expect_err("缺 msg 时回落 data");
        assert!(matches!(
            fallback,
            SliveError::Api { message, .. } if message == "房间已封禁"
        ));
    }
}