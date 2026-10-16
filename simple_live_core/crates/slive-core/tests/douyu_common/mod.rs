//! 斗鱼集成测试共享支撑：夹具加载 + 注入式站点构造（douyu 专属，不改共享 `tests/common`）。
#![allow(dead_code)]

use std::path::PathBuf;
use std::sync::Arc;

use serde_json::Value;
use slive_core::platforms::douyu::transport::MockDouyuPost;
use slive_core::platforms::douyu::DouyuSite;
use slive_core::testing::{FakeTime, MockTransport};

/// 固定时间戳（签名 `tt` 等 golden 用）。
pub const FIXED_TS: u64 = 1_700_000_000;

/// 夹具根目录。
pub fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/douyu")
}

/// 读取文本夹具。
pub fn read_text(rel: &str) -> String {
    let path = fixtures_dir().join(rel);
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("读取夹具 {rel} 失败: {e}"))
}

/// 读取二进制夹具。
pub fn read_bytes(rel: &str) -> Vec<u8> {
    let path = fixtures_dir().join(rel);
    std::fs::read(&path).unwrap_or_else(|e| panic!("读取夹具 {rel} 失败: {e}"))
}

/// 解析 `http/http-samples.json`。
pub fn http_samples() -> Value {
    serde_json::from_str(&read_text("http/http-samples.json")).expect("解析 http-samples.json")
}

/// 取某端点的样本。
pub fn sample(key: &str) -> Value {
    http_samples()["samples"][key].clone()
}

/// 样本响应体（JSON 串）。
pub fn sample_response(key: &str) -> String {
    serde_json::to_string(&sample(key)["response"]).expect("序列化样本响应")
}

/// 变体响应体（JSON 串）。
pub fn variant_response(key: &str, index: usize) -> String {
    serde_json::to_string(&sample(key)["variants"][index]["response"]).expect("序列化变体响应")
}

/// 样本/变体的 `expected`。
pub fn expected(key: &str) -> Value {
    sample(key)["expected"].clone()
}

pub fn variant_expected(key: &str, index: usize) -> Value {
    sample(key)["variants"][index]["expected"].clone()
}

/// 端点 -> mock 匹配键：去 scheme / query，并**逐段剥离**末尾的 `{xxx}` 路径参数。
///
/// 形如 `https://www.douyu.com/gapi/rkc/directory/mixList/2_{cateId}/{page}`
/// -> `www.douyu.com/gapi/rkc/directory/mixList`（逐段剥离，保留目录前缀避免误匹配）。
pub fn endpoint_key(endpoint: &str) -> String {
    let without_scheme = endpoint.split("://").nth(1).unwrap_or(endpoint);
    let path = without_scheme.split('?').next().unwrap_or("");
    let mut segments: Vec<&str> = path.split('/').collect();
    while segments
        .last()
        .map(|s| s.contains('{') && s.ends_with('}'))
        .unwrap_or(false)
    {
        segments.pop();
    }
    segments.join("/")
}

/// 斗鱼测试站点 + mock/时间句柄。
pub struct Harness {
    /// 被测站点。
    pub site: DouyuSite,
    /// GET mock（记录请求）。
    pub get: Arc<MockTransport>,
    /// POST mock（记录请求）。
    pub post: Arc<MockDouyuPost>,
    /// 注入的时间源。
    pub time: Arc<FakeTime>,
}

/// 构造注入式站点。
pub fn harness() -> Harness {
    let get = Arc::new(MockTransport::new());
    let post = Arc::new(MockDouyuPost::new());
    let time = Arc::new(FakeTime::new(FIXED_TS));
    let site = DouyuSite::with_deps(get.clone(), post.clone(), time.clone());
    Harness {
        site,
        get,
        post,
        time,
    }
}

impl Harness {
    /// 按夹具 key 注册端点样本（GET）。
    pub fn stub_sample(&self, fixture_key: &str) {
        let key = endpoint_key(sample(fixture_key)["endpoint"].as_str().expect("endpoint"));
        self.get.stub(&key, &sample_response(fixture_key));
    }

    /// 注册端点样本（POST form）。
    pub fn stub_post_sample(&self, fixture_key: &str) {
        let key = endpoint_key(sample(fixture_key)["endpoint"].as_str().expect("endpoint"));
        self.post.stub(&key, &sample_response(fixture_key));
    }

    /// 注册带 `set-cookie` 的 GET 样本（safeAuth / 扫码轮询用）。
    pub fn stub_sample_with_cookie(&self, fixture_key: &str, set_cookie: Vec<String>) {
        let key = endpoint_key(sample(fixture_key)["endpoint"].as_str().expect("endpoint"));
        self.get
            .stub_with_cookie(&key, &sample_response(fixture_key), set_cookie);
    }

    /// 注册 `getEncryption`（签名所需）。
    pub fn stub_encryption(&self) {
        self.stub_sample("www_douyu_com_wgapi_livenc_liveweb_websec_getEncryption");
    }
}

/// 构造一个最小 [`slive_core::models::LiveRoomDetail`]。
pub fn detail(room_id: &str) -> slive_core::models::LiveRoomDetail {
    slive_core::models::LiveRoomDetail {
        room_id: room_id.to_string(),
        title: String::new(),
        cover: String::new(),
        user_name: String::new(),
        user_avatar: String::new(),
        online: 0,
        introduction: None,
        notice: None,
        status: true,
        data: None,
        danmaku_data: None,
        is_record: false,
        url: format!("https://www.douyu.com/{room_id}"),
    }
}