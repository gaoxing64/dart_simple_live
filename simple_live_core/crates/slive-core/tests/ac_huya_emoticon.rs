//! 虎牙大表情：TUP 拉取、静态兜底、会话注入的离线用例。

use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use slive_core::error::SliveError;
use slive_core::http::HttpReply;
use slive_core::models::{LiveDanmuItem, LiveMessageType};
use slive_core::platforms::huya::danmaku::args::HuyaDanmakuArgs;
use slive_core::platforms::huya::danmaku::emoticon::{static_table, HuyaEmoticon};
use slive_core::platforms::huya::danmaku::tars_emoticon::{
    ExpressionEmoticon, ExpressionEmoticonPackage, GetExpressionEmoticonPackageRsp,
};
use slive_core::platforms::huya::danmaku::{frames, run_session_with_emoticons, ConnectFactory};
use slive_core::platforms::huya::tup::{
    build_tup_response, fetch_emoticon_table, fetch_emoticon_table_with_timeout, PostBytesRequest,
    PostBytesTransport, FUNC_EXPRESSION_PACKAGES, SERVANT_WUP_UI,
};
use slive_core::platforms::huya::HuyaSite;
use slive_core::tars::{TarsEncoder, TarsValue};
use slive_core::testing::{FakeTime, MockTransport, ScriptedFrameSource};
use slive_core::ws::{FrameSource, SessionTuning};

struct MockPost {
    responses: Vec<Vec<u8>>,
    delay: Option<Duration>,
    requests: Mutex<Vec<PostBytesRequest>>,
}

#[async_trait]
impl PostBytesTransport for MockPost {
    async fn post_bytes(&self, request: &PostBytesRequest) -> Result<HttpReply, SliveError> {
        self.requests.lock().expect("锁").push(request.clone());
        if let Some(delay) = self.delay {
            tokio::time::sleep(delay).await;
        }
        let body = self
            .responses
            .first()
            .cloned()
            .ok_or_else(|| SliveError::network("MockPost 无可用响应"))?;
        Ok(HttpReply {
            status: 200,
            text: body.iter().map(|b| *b as char).collect(),
            set_cookie: Vec::new(),
        })
    }
}

fn site_with_post(post: Arc<MockPost>) -> HuyaSite {
    let get = Arc::new(MockTransport::new());
    HuyaSite::with_deps(
        Arc::clone(&get) as Arc<_>,
        Arc::clone(&post) as Arc<_>,
        Arc::new(FakeTime::new(0)),
    )
}

fn room_emote_rsp() -> GetExpressionEmoticonPackageRsp {
    GetExpressionEmoticonPackageRsp {
        s_message: String::new(),
        v_package: vec![ExpressionEmoticonPackage {
            s_package_id: "571".to_string(),
            s_name: "itai大表情".to_string(),
            i_type: 3,
            v_emoticon: vec![ExpressionEmoticon {
                s_name: "[墨镜小哥]".to_string(),
                i_type: 3,
                s_flexi_url: "https://fileserver.cdn.huya.com/x/expressconfig/steam.png"
                    .to_string(),
                ..Default::default()
            }],
            ..Default::default()
        }],
    }
}

fn tup_body() -> Vec<u8> {
    build_tup_response(
        SERVANT_WUP_UI,
        FUNC_EXPRESSION_PACKAGES,
        0,
        Some(&room_emote_rsp()),
    )
    .expect("构造 TUP 响应")
}

#[tokio::test]
async fn fetch_table_merges_room_package_into_static_table() {
    let post = Arc::new(MockPost {
        responses: vec![tup_body()],
        delay: None,
        requests: Mutex::new(Vec::new()),
    });
    let site = site_with_post(post);
    let table = fetch_emoticon_table(&site, 1199517808234).await;

    let emoticon = table.get("[墨镜小哥]").expect("应合并房间大表情");
    assert_eq!(
        emoticon.url,
        "https://fileserver.cdn.huya.com/x/expressconfig/steam_3.png"
    );
    assert!(emoticon.large);
    assert!(table.contains_key("[666]"), "静态 97 项兜底保留");
}

#[tokio::test]
async fn fetch_table_falls_back_to_static_on_error() {
    let post = Arc::new(MockPost {
        responses: Vec::new(),
        delay: None,
        requests: Mutex::new(Vec::new()),
    });
    let site = site_with_post(post);
    let table = fetch_emoticon_table(&site, 123).await;

    assert_eq!(table.len(), 97, "失败必须回退静态表");
    assert!(table.contains_key("[666]"));
    assert!(!table.contains_key("[墨镜小哥]"));
}

#[tokio::test]
async fn fetch_table_falls_back_to_static_on_timeout() {
    let post = Arc::new(MockPost {
        responses: vec![tup_body()],
        delay: Some(Duration::from_millis(100)),
        requests: Mutex::new(Vec::new()),
    });
    let site = site_with_post(post);
    let table = fetch_emoticon_table_with_timeout(&site, 123, Duration::from_millis(10)).await;

    assert_eq!(table.len(), 97, "超时必须回退静态表");
    assert!(!table.contains_key("[墨镜小哥]"));
}

/// 合成一条服务端形态的 `uri=1400` 聊天帧（bare 字段表）。
fn chat_frame(content: &str) -> Vec<u8> {
    let mut message = TarsEncoder::new();
    message
        .write_value(&TarsValue::Struct(vec![(2, TarsValue::string("观众"))]), 0)
        .expect("userInfo");
    message.write_string(content, 3).expect("content");
    message
        .write_value(&TarsValue::Struct(vec![(0, TarsValue::int(0))]), 6)
        .expect("bulletFormat");

    let mut push = TarsEncoder::new();
    push.write_i64(0, 0).expect("pushType");
    push.write_i64(frames::URI_CHAT, 1).expect("uri");
    push.write_bytes(&message.into_bytes(), 2).expect("msg");
    push.write_i64(0, 3).expect("protocolType");
    frames::build_command(frames::cmd::MSG_PUSH_REQ, &push.into_bytes()).expect("command")
}

#[tokio::test]
async fn session_uses_dynamic_table_for_large_emote() {
    let mut queue: std::collections::VecDeque<Box<dyn FrameSource>> =
        std::collections::VecDeque::new();
    queue.push_back(Box::new(ScriptedFrameSource::new(vec![chat_frame(
        "[墨镜小哥]",
    )])));
    let connect: ConnectFactory = Box::new(move || {
        let next = queue.pop_front();
        Box::pin(async move { next.ok_or_else(|| SliveError::network("无更多连接")) })
    });

    let mut table = static_table();
    table.insert(
        "[墨镜小哥]".to_string(),
        HuyaEmoticon {
            url: "https://x/steam_3.png".to_string(),
            large: true,
        },
    );
    let items: Arc<Mutex<Vec<LiveDanmuItem>>> = Arc::new(Mutex::new(Vec::new()));
    let sink = Arc::clone(&items);
    let (_stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    run_session_with_emoticons(
        HuyaDanmakuArgs::new(1, 660_000, 660_001),
        connect,
        Arc::new(FakeTime::new(0)),
        SessionTuning::bilibili(),
        stop_rx,
        None,
        table,
        move |item| sink.lock().expect("锁").push(item),
    )
    .await;

    let got = items.lock().expect("锁").clone();
    let message = got
        .iter()
        .find_map(|item| match item {
            LiveDanmuItem::Message(message) if message.message_type == LiveMessageType::Chat => {
                Some(message)
            }
            _ => None,
        })
        .expect("应收到聊天消息");
    assert_eq!(message.message, "[墨镜小哥]");
    let emoticon = &message.emoticons.as_ref().expect("应带表情")[0];
    assert_eq!(emoticon.name.as_deref(), Some("[墨镜小哥]"));
    assert_eq!(emoticon.url, "https://x/steam_3.png");
    assert!(emoticon.large);
}
