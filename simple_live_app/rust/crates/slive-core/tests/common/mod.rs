//! 集成测试共享支撑：夹具加载 + 注入式站点构造。
#![allow(dead_code)]

use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use serde_json::Value;
use slive_core::platforms::bilibili::BilibiliSite;
use slive_core::testing::{CaptureLogger, FakeTime, MockTransport};

/// 固定 wbi 时间戳（与 golden-wbi.json 一致）。
pub const FIXED_WTS: u64 = 1_700_000_000;

/// 夹具根目录。
pub fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/bilibili")
}

/// 读取文本夹具。
pub fn read_text(rel: &str) -> String {
    std::fs::read_to_string(fixtures_dir().join(rel))
        .unwrap_or_else(|e| panic!("读取夹具 {rel} 失败: {e}"))
}

/// 读取二进制夹具。
pub fn read_bytes(rel: &str) -> Vec<u8> {
    std::fs::read(fixtures_dir().join(rel)).unwrap_or_else(|e| panic!("读取夹具 {rel} 失败: {e}"))
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

/// 端点 -> mock 匹配键（去 scheme，去 query）。
pub fn endpoint_key(endpoint: &str) -> String {
    let without_scheme = endpoint.split("://").nth(1).unwrap_or(endpoint);
    without_scheme.split('?').next().unwrap_or("").to_string()
}

/// 测试站点 + mock/时间句柄。
pub struct Harness {
    /// 被测站点。
    pub site: BilibiliSite,
    /// mock 传输（记录请求）。
    pub mock: Arc<MockTransport>,
    /// 注入的时间源。
    pub time: Arc<FakeTime>,
}

/// 构造注入式站点。
pub fn harness() -> Harness {
    let mock = Arc::new(MockTransport::new());
    let time = Arc::new(FakeTime::new(FIXED_WTS));
    let site = BilibiliSite::with_deps(mock.clone(), time.clone());
    Harness { site, mock, time }
}

impl Harness {
    /// 按夹具 key 注册端点样本。
    pub fn stub_sample(&self, fixture_key: &str) {
        let endpoint = endpoint_key(
            sample(fixture_key)["endpoint"]
                .as_str()
                .expect("endpoint 字段"),
        );
        self.mock.stub(&endpoint, &sample_response(fixture_key));
    }

    /// 注册 wbi keys 响应（`nav` 样本）。
    pub fn stub_wbi_keys(&self) {
        self.stub_sample("x_web-interface_nav");
    }

    /// 注册 `access_id` 响应（`live.bilibili.com/lol` 的 HTML 文本）。
    pub fn stub_access_id(&self) {
        let html = sample("live.bilibili.com_lol")["response"]
            .as_str()
            .expect("lol 样本为 HTML 字符串")
            .to_string();
        self.mock.stub("live.bilibili.com/lol", &html);
    }

    /// 注册 buvid SPI 响应。
    pub fn stub_buvid(&self) {
        self.stub_sample("x_frontend_finger_spi");
    }
}

/// 进程内单例日志捕获器（AC-40）。
pub fn capture_logger() -> Arc<CaptureLogger> {
    static LOGGER: OnceLock<Arc<CaptureLogger>> = OnceLock::new();
    LOGGER.get_or_init(CaptureLogger::install).clone()
}

/// 构造一个最小 [`LiveRoomDetail`]（供取流用例）。
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
        url: format!("https://live.bilibili.com/{room_id}"),
    }
}

/// 构造一个最小 [`LivePlayQuality`]（`data` 为 qn 十进制串）。
pub fn quality(data: &str) -> slive_core::models::LivePlayQuality {
    slive_core::models::LivePlayQuality {
        quality: "x".to_string(),
        data: data.to_string(),
        sort: 0,
    }
}
