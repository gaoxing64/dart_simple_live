//! `#[cfg(test)]` 测试体（从 `session.rs` 拆出，避免单文件超 300 行硬门禁）。

    use super::*;
    use crate::models::LiveMessageType;
    use crate::testing::{FakeTime, ScriptedFrameSource};
    use std::collections::VecDeque;
    use std::sync::Mutex as StdMutex;

    fn args() -> TwitchDanmakuArgs {
        TwitchDanmakuArgs::new("xqc")
    }

    fn collector() -> (
        Arc<StdMutex<Vec<LiveDanmuItem>>>,
        impl FnMut(LiveDanmuItem) + Send,
    ) {
        let items: Arc<StdMutex<Vec<LiveDanmuItem>>> = Arc::new(StdMutex::new(Vec::new()));
        let sink = Arc::clone(&items);
        (items, move |item| sink.lock().expect("sink").push(item))
    }

    /// 把每帧的时间推进 `advance` 秒（用于确定性触发心跳）。
    struct TimeAdvancingSource {
        inner: ScriptedFrameSource,
        time: Arc<FakeTime>,
        advanced: bool,
        advance: u64,
        sent: Arc<StdMutex<Vec<Vec<u8>>>>,
    }

    #[async_trait::async_trait]
    impl FrameSource for TimeAdvancingSource {
        async fn next_frame(&mut self) -> Option<Result<Vec<u8>, SliveError>> {
            if !self.advanced {
                self.advanced = true;
                self.time.advance(self.advance);
            }
            self.inner.next_frame().await
        }

        async fn send(&mut self, frame: Vec<u8>) -> Result<(), SliveError> {
            self.sent.lock().expect("sent").push(frame.clone());
            self.inner.send(frame).await
        }
    }

    #[test]
    fn tuning_matches_dart() {
        let t = tuning();
        assert_eq!(t.heartbeat_secs, 40);
        assert_eq!(t.reconnect_delay_secs, 5);
        assert_eq!(t.max_reconnect, 5);
    }

    #[tokio::test]
    async fn handshake_then_chat_message_then_closed() {
        let privmsg = "@display-name=Alice;color=#00FF00;user-id=42 \
                       :alice!alice@alice.tmi.twitch.tv PRIVMSG #xqc :hello"
            .as_bytes()
            .to_vec();
        let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
        queue.push_back(Box::new(ScriptedFrameSource::new(vec![privmsg])));

        let sent: Arc<StdMutex<Vec<Vec<u8>>>> = Arc::new(StdMutex::new(Vec::new()));
        // 用一个共享 sent 的包装源不可行（source 由工厂创建），改为只断言事件。
        let _ = sent;

        let connect: TwitchConnectFactory = Box::new(move || {
            let next = queue.pop_front();
            Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
        });
        let (items, on_item) = collector();
        let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);
        run_session(
            args(),
            connect,
            Arc::new(FakeTime::new(1_700_000_000)),
            tuning(),
            stop_rx,
            on_item,
        )
        .await;

        let got = items.lock().expect("items").clone();
        assert!(matches!(
            got.first(),
            Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Ready))
        ));
        assert!(
            matches!(&got[1], LiveDanmuItem::Message(m) if m.message == "hello" && m.user_name == "Alice"),
            "PRIVMSG 应分发为聊天消息，实际 {:?}",
            got.get(1)
        );
        assert_eq!(
            got.iter()
                .filter(|i| matches!(
                    i,
                    LiveDanmuItem::Control(LiveDanmuControlEvent::Reconnecting { .. })
                ))
                .count(),
            5,
            "最多 5 次重连（5s×5）"
        );
        assert!(matches!(
            got.last(),
            Some(LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(_)))
        ));
    }

    #[tokio::test]
    async fn ping_is_answered_with_pong_and_heartbeat_after_40s() {
        let time = Arc::new(FakeTime::new(1_700_000_000));
        let sent: Arc<StdMutex<Vec<Vec<u8>>>> = Arc::new(StdMutex::new(Vec::new()));
        let mut queue: VecDeque<Box<dyn FrameSource>> = VecDeque::new();
        queue.push_back(Box::new(TimeAdvancingSource {
            inner: ScriptedFrameSource::new(vec![b"PING :tmi.twitch.tv\n".to_vec()]),
            time: Arc::clone(&time),
            advanced: false,
            advance: 40,
            sent: Arc::clone(&sent),
        }));
        let connect: TwitchConnectFactory = Box::new(move || {
            let next = queue.pop_front();
            Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
        });
        let (items, on_item) = collector();
        let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);
        run_session(args(), connect, time, tuning(), stop_rx, on_item).await;

        let got = sent.lock().expect("sent");
        let texts: Vec<String> = got
            .iter()
            .map(|f| String::from_utf8_lossy(f).to_string())
            .collect();
        assert_eq!(texts.len(), 7, "握手 5 帧 + 心跳 1 帧 + PONG 应答 1 帧");
        assert!(texts[0].starts_with("CAP REQ"));
        assert_eq!(texts[4], "JOIN #xqc");
        assert_eq!(texts[5], "PONG :tmi.twitch.tv", "40s 到期发心跳（Dart 载荷）");
        // Q-B/Q8（钉死）：应答 = 整帧 `replaceFirst` 结果，保留帧尾换行。
        assert_eq!(
            texts[6], "PONG :tmi.twitch.tv\n",
            "服务端 PING 的应答按 Dart 整帧替换（含尾随换行）"
        );
        let _ = items.lock().expect("items").len();
    }

    #[tokio::test]
    async fn stop_signal_before_connect_emits_closed_without_connecting() {
        // 预置 stop：会话必须在**尝试连接之前**收敛（桥层 `stop()` 与 `start()` 竞态时
        // 会走到这条路径 —— 不能白连一次 IRC）。
        let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);
        stop_tx.send(true).expect("预置 stop");
        let connect: TwitchConnectFactory = Box::new(|| panic!("已置 stop 时不得尝试连接"));
        let (items, on_item) = collector();
        run_session(
            args(),
            connect,
            Arc::new(FakeTime::new(0)),
            tuning(),
            stop_rx,
            on_item,
        )
        .await;

        let got = items.lock().expect("items").clone();
        assert_eq!(got.len(), 1, "只应发一条事件，实际 {got:?}");
        assert!(
            matches!(&got[0], LiveDanmuItem::Control(LiveDanmuControlEvent::Closed(msg)) if msg == "已手动停止"),
            "实际 {got:?}"
        );
    }

    #[tokio::test]
    async fn message_type_is_chat_for_privmsg() {
        let out = parse_frame("@display-name=A;color=#FFFFFF :a!a@a PRIVMSG #xqc :hey");
        assert_eq!(out.messages[0].message_type, LiveMessageType::Chat);
    }
