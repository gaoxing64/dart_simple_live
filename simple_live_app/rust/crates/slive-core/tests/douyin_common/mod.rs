//! 抖音离线夹具加载 + 注入式站点构造（与 B站 `common` 同构，但绑定抖音夹具目录）。
#![allow(dead_code)]

use std::path::PathBuf;
use std::sync::Arc;

use slive_core::platforms::douyin::DouyinSite;
use slive_core::testing::{FakeTime, MockTransport};

/// 固定时间戳（供 `FakeTime` 与需要确定性时间的用例使用）。
pub const FIXED_WTS: u64 = 1_700_000_000;

/// 夹具里的 ttwid 值（`ensure_ttwid` 取出后应前置到 cookie）。
pub const TTWID_VALUE: &str = "ttwid=1%2Cfixture%2Cfixture";

/// 抖音夹具根目录。
pub fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/douyin")
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

/// 抖音测试站点 + mock 句柄。
pub struct Harness {
    /// 被测站点。
    pub site: DouyinSite,
    /// mock 传输（记录请求）。
    pub mock: Arc<MockTransport>,
    /// 注入的时间源。
    pub time: Arc<FakeTime>,
}

/// 构造注入式站点。
pub fn harness() -> Harness {
    let mock = Arc::new(MockTransport::new());
    let time = Arc::new(FakeTime::new(FIXED_WTS));
    let site = DouyinSite::with_deps(mock.clone(), time.clone());
    Harness { site, mock, time }
}

impl Harness {
    /// 注册首页 HTML 夹具（分类数据来源 + ttwid 下发）。
    ///
    /// ⚠️ **必须最后注册**：`MockTransport` 按**注册顺序**取第一个命中的 stub，
    /// 而本 key 是 `live.douyin.com`（抖音所有端点的公共前缀），先注册会**遮蔽**
    /// 所有分区 / feed / enter 夹具。故它是「兜底」夹具：具体端点夹具注册在前、
    /// 本方法注册在后，命中顺序才正确。
    ///
    /// 顺带下发 ttwid：`ensure_ttwid` 的取 cookie 请求与分类数据请求**是同一个 URL**
    /// （`https://live.douyin.com`，Dart 用 HEAD + GET 区分方法，core 的
    /// [`slive_core::http::HttpTransport`] 只暴露 GET），故一次性满足两种用途。
    pub fn stub_home_html(&self, key: &str) {
        self.mock.stub_with_cookie(
            "live.douyin.com",
            &read_text(&format!("http/{key}.html")),
            vec![format!("{TTWID_VALUE}; Path=/; HttpOnly")],
        );
    }

    /// 注册 JSON 端点夹具（按 URL 子串匹配；键取路径中较独特的一段）。
    ///
    /// 键应**长于** `live.douyin.com`，以保证在兜底夹具之前命中。
    pub fn stub_json(&self, url_key: &str, fixture_key: &str) {
        self.mock
            .stub(url_key, &read_text(&format!("http/{fixture_key}.json")));
    }

    /// 注册任意 JSON 端点夹具（内联响应体）。
    pub fn stub_json_inline(&self, url_key: &str, body: &str) {
        self.mock.stub(url_key, body);
    }

    /// 注册 HTML 端点夹具（内联响应体）。
    pub fn stub_text_inline(&self, url_key: &str, body: &str) {
        self.mock.stub(url_key, body);
    }

    /// 注册 HTTP 错误夹具。
    pub fn stub_http_error(&self, url_key: &str, status: u16) {
        self.mock.stub_http_error(url_key, status);
    }

    /// 注册传输层失败夹具。
    pub fn stub_network_error(&self, url_key: &str, message: &str) {
        self.mock.stub_network_error(url_key, message);
    }

    /// 站点当前 cookie（断言 ttwid 是否被吸收）。
    pub fn cookie(&self) -> String {
        self.site.header_cookie()
    }

    /// 某 URL 段的请求次数（AC「不引入额外往返」断言）。
    pub fn request_count(&self, key: &str) -> usize {
        self.mock.request_count(key)
    }

    /// 记录到的全部请求 URL（含 query 摘要）。
    pub fn request_urls(&self) -> Vec<String> {
        self.mock.request_urls()
    }
}
