//! `#[cfg(test)]` 测试体（从 `site.rs` 拆出，避免单文件超 300 行硬门禁）。

    use super::*;
    use crate::testing::FakeTime;

    #[test]
    fn id_and_name_match_dart() {
        let site = TwitchSite::new();
        assert_eq!(site.id(), "twitch");
        assert_eq!(site.name(), "Twitch");
    }

    #[test]
    fn device_id_is_handle_level_and_stable() {
        let time = Arc::new(FakeTime::new(1_700_000_000));
        let site = TwitchSite::with_deps(
            Arc::new(crate::testing::MockTransport::new()),
            Arc::new(super::super::transport::MockTwitchPost::new()),
            time.clone(),
        );
        let first = site.device_id();
        assert_eq!(first, site.device_id(), "同句柄应稳定");
        time.advance(5);
        assert_eq!(first, site.device_id(), "时间推进不改变已缓存的 device-id");
        assert_eq!(
            first.parse::<u64>().expect("数字"),
            DEVICE_ID_BASE + 1_700_000_000 % DEVICE_ID_SPAN,
            "值由注入时间源派生"
        );

        site.set_device_id("4242424242424242");
        assert_eq!(site.device_id(), "4242424242424242", "可显式覆盖");
    }

    #[tokio::test]
    async fn live_status_reuses_detail_chain() {
        let mock = Arc::new(super::super::transport::MockTwitchPost::new());
        mock.stub(
            "gql.twitch.tv",
            r#"[{"data":{"userOrError":{"displayName":"XQC","profileImageURL":"https://a/p.jpg","__typename":"User"}}},
                {"data":{"user":{"profileImageURL":"https://a/c.jpg","stream":{"viewersCount":42,"type":"live"},"__typename":"User"}}}]"#,
        );
        let site = TwitchSite::with_deps(
            Arc::new(crate::testing::MockTransport::new()),
            mock.clone(),
            Arc::new(FakeTime::new(1_700_000_000)),
        );
        assert!(site.get_live_status("xqc".to_string()).await.expect("状态"));
        assert_eq!(mock.request_count("gql.twitch.tv"), 1, "只请求一次");
    }
