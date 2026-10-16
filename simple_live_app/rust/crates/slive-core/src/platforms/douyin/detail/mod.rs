//! 房间详情（对照 Dart `getRoomDetail` 全家桶，`douyin_site.dart:494-946`）。
//!
//! # 两种房间号
//!
//! - `webRid`：固定，11~12 位（如 `416144012050`），首页/推荐下发的就是它；
//! - `roomId`：一次性，19 位（如 `7376429659866598196`），主播每次重开播都会换。
//!
//! Dart 用**长度 ≤ 16** 判定是哪个（`douyin_site.dart:502`），此处照抄。
//!
//! # 三段降级（少一段就有房间进不去）
//! ```text
//! roomId(19) ──> reflow/info ──┐
//!                              ├─> 房间数据 ──> LiveRoomDetail
//! webRid(≤16) ─> web/enter ────┤
//!                └(失败)─> 页面 HTML ─┘
//! ```
//! 关键修补点（照抄 Dart 的实测结论，勿「简化」）：
//! - 19 位 `roomId` **必须先走 `reflow/info`**，不能先转 webRid 再走 `web/enter`：
//!   连麦 / 多人连线房间下 `web/enter` 会返回「降级房间」（只剩 22 个字段的骨架，
//!   `status != 2` 且无 `stream_url`），后续取画质会直接崩，直播间根本进不去；
//! - `web/enter` 返回的 `stream_url` 为空时，用它给的 `roomId` **整体采信**
//!   `reflow/info` 的结果（首页 / 推荐 / 关注列表下发的都是 webRid，全走这条链路，
//!   不做这个补救则连麦房间会被判成「未开播」）。

mod builder;
mod enter;
mod html;
mod reflow;

pub use enter::enter_params;
pub use reflow::reflow_params;

use crate::error::SliveError;
use crate::models::LiveRoomDetail;

use super::site::DouyinSite;

/// 直播间页面 URL 前缀。
pub const ROOM_PAGE_URL: &str = "https://live.douyin.com/";
/// `roomId.length <= 16` 判定为 webRid（Dart `douyin_site.dart:502`）。
pub const WEB_RID_MAX_LEN: usize = 16;

/// 房间详情入口：按房间号长度分派。
pub(crate) async fn fetch(site: &DouyinSite, room_id: &str) -> Result<LiveRoomDetail, SliveError> {
    if room_id.chars().count() <= WEB_RID_MAX_LEN {
        return fetch_by_web_rid(site, room_id).await;
    }
    // 19 位 roomId 优先 reflow/info。
    // 只把「网络抖动 / 反爬拦截」这类意外兜底到 webRid 链路：刻意抛出的业务错误
    // （房间数据异常）直接上抛，避免多打 2~3 次重复请求。
    match reflow::fetch_by_room_id(site, room_id).await {
        Ok(detail) => Ok(detail),
        Err(e) if is_deliberate(&e) => Err(e),
        Err(e) => {
            log::warn!("抖音 reflow/info 链路失败，回退 webRid 链路: {e}");
            let web_rid = reflow::resolve_web_rid(site, room_id).await;
            fetch_by_web_rid(site, &web_rid).await
        }
    }
}

/// 该错误是否是「刻意抛出的业务错误」（值得直接上抛，不该再打重复请求）。
///
/// Dart 的判据是 `if (e is CoreError) rethrow` —— 即凡是被显式包装成 `CoreError` 的
/// （房间数据异常 / 未返回房间数据）都不兜底。这里对应 `Decode` / `NotFound` /
/// `InvalidInput`；`Network` / `Http` / `Api` 属「意外」，走兜底链路。
fn is_deliberate(err: &SliveError) -> bool {
    matches!(
        err,
        SliveError::Decode(_) | SliveError::NotFound(_) | SliveError::InvalidInput(_)
    )
}

/// 通过 webRid 获取详情：先 API，失败再走页面 HTML。
pub(crate) async fn fetch_by_web_rid(
    site: &DouyinSite,
    web_rid: &str,
) -> Result<LiveRoomDetail, SliveError> {
    match enter::fetch_by_web_rid_api(site, web_rid).await {
        Ok(detail) => Ok(detail),
        Err(e) => {
            log::warn!("抖音 web/enter 链路失败，回退页面 HTML: {e}");
            html::fetch_by_web_rid_html(site, web_rid).await
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_deliberate_separates_business_errors_from_transport() {
        assert!(is_deliberate(&SliveError::decode("x")));
        assert!(is_deliberate(&SliveError::not_found("x")));
        assert!(is_deliberate(&SliveError::invalid_input("x")));
        assert!(!is_deliberate(&SliveError::network("x")));
        assert!(!is_deliberate(&SliveError::Http { status: 403, body: String::new() }));
        assert!(!is_deliberate(&SliveError::Api { code: -352, message: String::new() }));
    }

    #[test]
    fn web_rid_length_threshold_matches_dart() {
        // Dart: roomId.length <= 16 视为 webRid
        assert!("416144012050".len() <= WEB_RID_MAX_LEN);
        assert!("7376429659866598196".len() > WEB_RID_MAX_LEN);
    }
}
