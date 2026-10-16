//! 直播状态（对照 Dart `getLiveStatus`，`douyin_site.dart:1177-1181`）。
//!
//! Dart 直接复用详情链路的 `result.status`（`room.status == 2`），**没有**独立接口。
//! 这里照抄：不新增轻量接口，保持请求集合与 Dart 同路径（§9 性能口径：
//! 「每类请求不得引入额外串行往返」）。

use crate::error::SliveError;

use super::site::DouyinSite;

/// 在播状态（复用 `get_room_detail` 的 `status`）。
pub(crate) async fn fetch(site: &DouyinSite, room_id: &str) -> Result<bool, SliveError> {
    Ok(super::detail::fetch(site, room_id).await?.status)
}

#[cfg(test)]
mod tests {
    use crate::error::SliveError;
    use crate::testing::{FakeTime, MockTransport};
    use std::sync::Arc;

    use super::fetch;
    use crate::platforms::douyin::DouyinSite;

    /// 构造带 enter 夹具与 ttwid 兜底的站点。
    ///
    /// ⚠️ **注册顺序**：具体端点夹具必须先注册，`live.douyin.com`（ttwid 兜底）后注册 ——
    /// `MockTransport` 按注册顺序取**第一个**命中的 stub，而 `live.douyin.com` 是所有
    /// 抖音端点的公共前缀，先注册会遮蔽 enter 夹具（表现为「未能获取房间信息」）。
    fn site_with_enter(status: i32) -> DouyinSite {
        let mock = Arc::new(MockTransport::new());
        mock.stub(
            "room/web/enter/",
            &format!(
                r#"{{"status_code":0,"data":{{"data":[{{"id_str":"7382735338101328680",
               "title":"t","status":{status},"owner":{{"nickname":"n","web_rid":"416144012050"}}}}]}}}}"#
            ),
        );
        mock.stub_with_cookie(
            "live.douyin.com",
            "",
            vec!["ttwid=1%2Cabc; Path=/".to_string()],
        );
        DouyinSite::with_deps(mock, Arc::new(FakeTime::new(0)))
    }

    #[tokio::test]
    async fn propagates_detail_errors_instead_of_defaulting_to_false() {
        // 注入「一个夹具都没注册」的 MockTransport：必须报错而不是静默 false
        // （静默 false 会让 App 显示「未开播」，掩盖真实故障）。
        // ⚠️ 不能用 `DouyinSite::new()`：那会走**真实网络**，单测会变成联网用例。
        let mock = Arc::new(MockTransport::new());
        let site = DouyinSite::with_deps(mock, Arc::new(FakeTime::new(0)));
        let err = fetch(&site, "416144012050").await.expect_err("应报错");
        assert!(matches!(err, SliveError::Network(_)), "实际 {err:?}");
    }

    #[tokio::test]
    async fn status_is_true_when_room_is_live() {
        assert!(
            fetch(&site_with_enter(2), "416144012050")
                .await
                .expect("应成功"),
            "status=2 应为在播"
        );
    }

    #[tokio::test]
    async fn status_is_false_when_room_is_offline() {
        assert!(
            !fetch(&site_with_enter(4), "416144012050")
                .await
                .expect("应成功"),
            "status=4 应为未播"
        );
    }
}
