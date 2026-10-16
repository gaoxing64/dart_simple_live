//! Twitch 集成测试共享支撑：夹具加载 + 注入式站点构造。
//!
//! 与 `tests/common/mod.rs`（B站）**并列而非复用**：后者硬编码 `BilibiliSite` 与 B站夹具
//! 路径，多平台并行期不改共享测试文件（由总监统一接线）。
//!
//! 夹具布局（均为**合成夹具**，`_meta.synthetic = true`，逐字段标注 Dart 行号）：
//! - `http/http-samples.json`：GQL 批量响应 / PlaybackAccessToken / usher m3u8（含 12 个变体）；
//! - `ws/*.bin` + `ws/*.expected.json`：IRC 帧 golden 对（含 `_meta.dart_would_behavior` 差异留痕）；
//! - `golden/golden-quality-name.json`：清晰度阈值表边界枚举；
//! - `heldout/`：留出集（实现者不可见，当前为空）。
#![allow(dead_code)]

use std::path::PathBuf;
use std::sync::Arc;

use serde_json::Value;
use slive_core::platforms::twitch::transport::MockTwitchPost;
use slive_core::platforms::twitch::TwitchSite;
use slive_core::testing::{FakeTime, MockTransport};

/// 固定时间戳（device-id / nick 派生用，保证可断言）。
pub const FIXED_WTS: u64 = 1_700_000_000;

/// 夹具根目录。
pub fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/twitch")
}

/// 读取文本夹具（相对 `fixtures/twitch`）。
pub fn read_text(rel: &str) -> String {
    std::fs::read_to_string(fixtures_dir().join(rel))
        .unwrap_or_else(|e| panic!("读取夹具 {rel} 失败: {e}"))
}

/// 读取二进制夹具（IRC 原始帧）。
pub fn read_bytes(rel: &str) -> Vec<u8> {
    std::fs::read(fixtures_dir().join(rel))
        .unwrap_or_else(|e| panic!("读取夹具 {rel} 失败: {e}"))
}

/// 解析 `http/http-samples.json`。
pub fn http_samples() -> Value {
    serde_json::from_str(&read_text("http/http-samples.json")).expect("解析 http-samples.json")
}

/// 取某个 HTTP 样本。
pub fn sample(key: &str) -> Value {
    http_samples()["samples"][key].clone()
}

/// 样本响应体（JSON 串）。文本样本（m3u8）走 [`sample_text`]。
pub fn sample_response(key: &str) -> String {
    serde_json::to_string(&sample(key)["response"]).expect("序列化样本响应")
}

/// 变体响应体（JSON 串）。
pub fn variant_response(key: &str, index: usize) -> String {
    serde_json::to_string(&sample(key)["variants"][index]["response"])
        .unwrap_or_else(|e| panic!("序列化变体 {key}#{index} 失败: {e}"))
}

/// 变体名（断言失败时给出可读信息）。
pub fn variant_name(key: &str, index: usize) -> String {
    sample(key)["variants"][index]["name"]
        .as_str()
        .unwrap_or_default()
        .to_string()
}

/// 文本类样本（m3u8 走 `__raw_m3u8` 承载，见夹具 `_meta.text_samples_note`）。
pub fn sample_text(key: &str) -> String {
    sample(key)["response"]["__raw_m3u8"]
        .as_str()
        .unwrap_or_else(|| panic!("样本 {key} 不是文本样本"))
        .to_string()
}

/// 变体文本（m3u8）。
pub fn variant_text(key: &str, index: usize) -> String {
    sample(key)["variants"][index]["response"]["__raw_m3u8"]
        .as_str()
        .unwrap_or_else(|| panic!("变体 {key}#{index} 不是文本样本"))
        .to_string()
}

/// 端点 -> mock 匹配键（去 scheme，去 query；Twitch GQL 是 POST，按 URL 子串匹配）。
pub fn endpoint_key(endpoint: &str) -> String {
    endpoint
        .split("://")
        .nth(1)
        .unwrap_or(endpoint)
        .split('?')
        .next()
        .unwrap_or("")
        .to_string()
}

/// 测试站点 + mock / 时间句柄。
pub struct Harness {
    /// 被测站点。
    pub site: TwitchSite,
    /// GQL POST mock（记录请求 body）。
    pub gql: Arc<MockTwitchPost>,
    /// usher m3u8 GET mock。
    pub http: Arc<MockTransport>,
    /// 注入的时间源。
    pub time: Arc<FakeTime>,
}

/// GQL 端点匹配键。
pub const GQL_KEY: &str = "gql.twitch.tv/gql";
/// usher m3u8 端点匹配键。
pub const PLAYLIST_KEY: &str = "usher.ttvnw.net";

impl Harness {
    /// 按样本 key 注册 GQL 响应（自动按样本 `endpoint` 匹配）。
    pub fn stub_gql_sample(&self, key: &str) {
        let endpoint = sample(key)["endpoint"]
            .as_str()
            .expect("endpoint 字段")
            .to_string();
        self.gql.stub(&endpoint_key(&endpoint), &sample_response(key));
    }

    /// 按变体注册 GQL 响应。
    pub fn stub_gql_variant(&self, key: &str, index: usize) {
        let endpoint = sample(key)["endpoint"]
            .as_str()
            .expect("endpoint 字段")
            .to_string();
        self.gql
            .stub(&endpoint_key(&endpoint), &variant_response(key, index));
    }

    /// 注册自定义 GQL 响应体。
    pub fn stub_gql_raw(&self, body: &str) {
        self.gql.stub(GQL_KEY, body);
    }

    /// 注册 m3u8 主播放列表（主样本）。
    pub fn stub_playlist(&self) {
        self.http
            .stub(PLAYLIST_KEY, &sample_text("usher_ttvnw_net_master_m3u8"));
    }

    /// 按变体注册 m3u8。
    pub fn stub_playlist_variant(&self, index: usize) {
        self.http.stub(
            PLAYLIST_KEY,
            &variant_text("usher_ttvnw_net_master_m3u8", index),
        );
    }

    /// 构造一个最小 [`slive_core::models::LiveRoomDetail`]（供取流用例）。
    pub fn detail(&self, room_id: &str, status: bool) -> slive_core::models::LiveRoomDetail {
        slive_core::models::LiveRoomDetail {
            room_id: room_id.to_string(),
            title: String::new(),
            cover: String::new(),
            user_name: String::new(),
            user_avatar: String::new(),
            online: 0,
            introduction: None,
            notice: None,
            status,
            data: None,
            danmaku_data: None,
            is_record: false,
            url: format!("https://www.twitch.tv/{room_id}"),
        }
    }

    /// 构造一个最小 [`slive_core::models::LivePlayQuality`]。
    pub fn quality(&self, data: &str) -> slive_core::models::LivePlayQuality {
        slive_core::models::LivePlayQuality {
            quality: "1080P".to_string(),
            data: data.to_string(),
            sort: 6_000_000,
        }
    }

    /// 已记录 GQL 请求的 body（解析为 JSON）。
    pub fn gql_bodies(&self) -> Vec<Value> {
        self.gql
            .requests()
            .iter()
            .map(|r| serde_json::from_str(&r.body).expect("请求体应为 JSON"))
            .collect()
    }
}

/// 构造注入式站点。
pub fn harness() -> Harness {
    let gql = Arc::new(MockTwitchPost::new());
    let http = Arc::new(MockTransport::new());
    let time = Arc::new(FakeTime::new(FIXED_WTS));
    let site = TwitchSite::with_deps(http.clone(), gql.clone(), time.clone());
    Harness {
        site,
        gql,
        http,
        time,
    }
}
