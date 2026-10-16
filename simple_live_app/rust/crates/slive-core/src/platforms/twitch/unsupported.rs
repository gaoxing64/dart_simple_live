//! Twitch 未实现/恒空能力（逐条对照 `twitch_site.dart`）。
//!
//! Dart core 里这些方法分两类，本模块保持同样区分（**不静默兜底**）：
//! - **恒空**（返回空列表 / 空结果，带注释「尚不支持」）：分类、分类下房间、SC 列表；
//! - **恒报错**（`throw UnimplementedError()` / `throw Exception(...)`）：推荐、搜索、
//!   凭证注入、账号信息、二维码、扫码轮询。
//!
//! 错误口径：`UnimplementedError` -> [`SliveError::InvalidInput`]（含「Dart core 亦未实现」后缀），
//! 显式 `Exception("twitch暂不支持搜索主播")` -> [`SliveError::Api`]`{code: -1}`
//! （与抖音模块对「暂不支持搜索主播」的口径一致，便于 App 侧统一提示）。

use crate::error::SliveError;
use crate::models::{
    LiveCategory, LiveCategoryResult, LiveSearchAnchorResult, LiveSearchRoomResult,
    LiveSuperChatMessage,
};

/// F-01 分类：Twitch 不做分类（对齐 Dart `return Future.value([])`）。
pub(crate) fn categories() -> Result<Vec<LiveCategory>, SliveError> {
    Ok(Vec::new())
}

/// F-02 分类下房间：恒空（对齐 Dart `LiveCategoryResult(hasMore: false, items: [])`）。
pub(crate) fn category_rooms() -> Result<LiveCategoryResult, SliveError> {
    Ok(LiveCategoryResult {
        has_more: false,
        items: Vec::new(),
    })
}

/// F-03 推荐房间：Dart `throw UnimplementedError()`。
pub(crate) fn recommend_rooms() -> Result<LiveCategoryResult, SliveError> {
    Err(unsupported("Twitch 不支持推荐房间"))
}

/// F-04 搜索房间：Dart `throw Exception("twitch暂不支持搜索房间")`。
pub(crate) fn search_rooms(
    _keyword: &str,
    _page: i32,
) -> Result<LiveSearchRoomResult, SliveError> {
    Err(SliveError::Api {
        code: -1,
        message: "twitch暂不支持搜索房间".to_string(),
    })
}

/// F-05 搜索主播：Dart `throw Exception("twitch暂不支持搜索主播")`。
pub(crate) fn search_anchors(
    _keyword: &str,
    _page: i32,
) -> Result<LiveSearchAnchorResult, SliveError> {
    Err(SliveError::Api {
        code: -1,
        message: "twitch暂不支持搜索主播".to_string(),
    })
}

/// F-10 SC 列表：恒空（对齐 Dart `return Future.value([])`）。
pub(crate) fn super_chat(_room_id: &str) -> Result<Vec<LiveSuperChatMessage>, SliveError> {
    Ok(Vec::new())
}

/// F-17 注入凭证：Dart `throw UnimplementedError()`（Twitch 匿名链路无 token/cookie）。
pub(crate) fn set_site_attrs(_data: &str) -> Result<(), SliveError> {
    Err(unsupported("Twitch 不支持注入凭证（匿名只读链路）"))
}

/// F-18 二维码：Dart `throw UnimplementedError()`。
pub(crate) fn qr_code() -> Result<crate::models::QrCode, SliveError> {
    Err(unsupported("Twitch 不支持二维码登录"))
}

/// F-19 扫码轮询：Dart `throw UnimplementedError()`。
pub(crate) fn qr_poll_result(_qrcode_key: &str) -> Result<crate::models::QrPollResult, SliveError> {
    Err(unsupported("Twitch 不支持扫码轮询"))
}

/// F-20 账号信息：Dart `throw UnimplementedError()`。
pub(crate) fn account_info(_credential: &str) -> Result<crate::models::AccountInfo, SliveError> {
    Err(unsupported("Twitch 不支持账号信息查询"))
}

/// 构造「平台未实现」错误（口径对齐 Dart `UnimplementedError`，映射为 `InvalidInput`）。
fn unsupported(what: &str) -> SliveError {
    SliveError::invalid_input(format!("{what}（Dart core 亦未实现）"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_capabilities_return_empty_not_error() {
        assert!(categories().expect("分类恒空").is_empty());
        let rooms = category_rooms().expect("分类房间恒空");
        assert!(!rooms.has_more && rooms.items.is_empty());
        assert!(super_chat("xqc").expect("SC 恒空").is_empty());
    }

    #[test]
    fn search_reports_dart_equivalent_api_error() {
        for err in [search_rooms("k", 1).err(), search_anchors("k", 1).err()] {
            match err.expect("搜索必须报错") {
                SliveError::Api { code, message } => {
                    assert_eq!(code, -1);
                    assert!(message.contains("暂不支持搜索"), "实际 {message}");
                }
                other => panic!("期望 Api(-1)，实际 {other:?}"),
            }
        }
    }

    #[test]
    fn unimplemented_methods_are_invalid_input() {
        for err in [
            recommend_rooms().err(),
            set_site_attrs("{}").err(),
            qr_code().err(),
            qr_poll_result("k").err(),
            account_info("c").err(),
        ] {
            let err = err.expect("未实现必须报错");
            assert!(
                matches!(err, SliveError::InvalidInput(_)),
                "未实现应为 InvalidInput，实际 {err:?}"
            );
        }
    }
}
