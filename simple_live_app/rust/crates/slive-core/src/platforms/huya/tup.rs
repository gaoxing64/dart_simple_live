//! TUP over HTTP 调用（对照 Dart `tars_dart/lib/tars/net/base_tars_http.dart`）。
//!
//! 虎牙两个 TARS HTTP 接口都在本模块：
//! - `liveui/getCdnTokenInfoEx`：换取取流 token（[`super::play`] 用）；
//! - `wupui/getHeadLineMessageBoard`：醒目留言列表（[`super::super_chat`] 与弹幕增量用）。
//!
//! 传输：虎牙的 TUP 走 **POST + 二进制 body**（`Content-Type: application/x-wup`），
//! 与常规 JSON GET 不同，故在 [`crate::http::HttpTransport`]（GET-only seam）之外
//! **另开一个 POST seam**（[`PostBytesTransport`]），保持测试可注入、不破坏既有 seam。
//!
//! 错误口径（对齐 Dart `BaseTarsHttp.tupRequest`）：`code != 0` -> [`SliveError::Api`]，
//! **不自动重试**（J-5 / AC-25）。

use std::collections::BTreeMap;

use async_trait::async_trait;

use crate::error::SliveError;
use crate::http::HttpReply;
use crate::tars::{TarsEncoder, TarsStruct, UniPacket};

use super::danmaku::args::{DEFAULT_DEVICE, DEFAULT_GUID};
use super::danmaku::tars_cdn::{GetCdnTokenExReq, GetCdnTokenExResp, HuyaUserId};
use super::danmaku::tars_sc::{GetGameEventMessageBoardReq, GetGameEventMessageBoardRsp};
use super::site::HuyaSite;

/// `liveui` servant（取流 token）。
pub const SERVANT_LIVE_UI: &str = "liveui";
/// `wupui` servant（醒目留言）。
pub const SERVANT_WUP_UI: &str = "wupui";
/// 取流 token 的函数名。
pub const FUNC_CDN_TOKEN_EX: &str = "getCdnTokenInfoEx";
/// 醒目留言的函数名。
pub const FUNC_HEADLINE_BOARD: &str = "getHeadLineMessageBoard";
/// TUP 请求的 Content-Type。
pub const TUP_CONTENT_TYPE: &str = "application/x-wup";

/// 匿名 `HuyaUserId`（对齐 Dart：仅带 UA，其余留空）。
///
/// cookie 字段 Dart 填了一大串真实匿名 cookie；该串**只用于风控识别**，
/// Rust 侧沿用同一常量以保证行为一致（**不写入日志**，AC-40）。
pub const ANON_COOKIE: &str = "__yamid_new=CB839821F9D0000153B312C11F40C3A0; game_did=c2NmeJsovdYnQ--7ekVF9JDx9YgQBaX9Xb4; SoundValue=0.50; guid=0a7d4b0826af6c69380199dc9adc6b50; udb_appid=5002; udb_deviceid=w_1143239981674745856; isInLiveRoom=true; udb_passdata=3; huya_flash_rep_cnt=60; huya_web_rep_cnt=214";

/// 构造匿名用户标识（`sHuYaUA` 由调用方给出随机 UA）。
pub fn anon_user_id(huya_ua: &str) -> HuyaUserId {
    HuyaUserId {
        l_uid: 0,
        s_guid: DEFAULT_GUID.to_string(),
        s_token: String::new(),
        s_huya_ua: huya_ua.to_string(),
        s_cookie: ANON_COOKIE.to_string(),
        i_token_type: 0,
        s_device_info: DEFAULT_DEVICE.to_string(),
        s_qimei: String::new(),
    }
}

/// 一次 POST 请求的描述（`MockPostTransport` 依此匹配与记录）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PostBytesRequest {
    /// 目标 URL。
    pub url: String,
    /// 请求头（顺序保留）。
    pub headers: Vec<(String, String)>,
    /// 二进制 body（TUP 封包字节）。
    pub body: Vec<u8>,
}

/// 二进制 POST 传输抽象（虎牙 TUP 专用 seam）。
#[async_trait]
pub trait PostBytesTransport: Send + Sync {
    /// 发送一次 POST。
    async fn post_bytes(&self, request: &PostBytesRequest) -> Result<HttpReply, SliveError>;
}

/// 生产实现：`reqwest`（复用 crate 的 `build_client`，保持与 GET 侧同一 TLS 栈）。
pub struct ReqwestPostTransport {
    client: reqwest::Client,
}

impl ReqwestPostTransport {
    /// 生产构造。
    pub fn new() -> Self {
        Self {
            client: crate::http::build_client(),
        }
    }
}

impl Default for ReqwestPostTransport {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl PostBytesTransport for ReqwestPostTransport {
    async fn post_bytes(&self, request: &PostBytesRequest) -> Result<HttpReply, SliveError> {
        let mut builder = self
            .client
            .post(reqwest::Url::parse(&request.url).map_err(|e| {
                SliveError::invalid_input(format!("非法 URL({}): {e}", request.url))
            })?)
            .body(request.body.clone())
            // TUP 是二进制协议，必须显式覆盖 reqwest 对 Vec<u8> 的默认 JSON 推断
            .header(reqwest::header::CONTENT_TYPE, TUP_CONTENT_TYPE);
        for (key, value) in &request.headers {
            builder = builder.header(key.as_str(), value.as_str());
        }

        let response = builder
            .send()
            .await
            .map_err(|e| SliveError::network(e.to_string()))?;
        let status = response.status().as_u16();
        let bytes = response
            .bytes()
            .await
            .map_err(|e| SliveError::network(format!("读取响应体失败: {e}")))?;
        if !(200..400).contains(&status) {
            return Err(SliveError::Http {
                status,
                body: String::from_utf8_lossy(&bytes).chars().take(512).collect(),
            });
        }
        Ok(HttpReply {
            status,
            // 二进制 body 以 latin-1 映射回String 承载（无损），调用方按字节取回
            text: bytes.iter().map(|b| *b as char).collect(),
            set_cookie: Vec::new(),
        })
    }
}

/// 把 [`HttpReply::text`] 还原为字节（TUP 响应是二进制，承载方式见上）。
pub fn reply_bytes(reply: &HttpReply) -> Vec<u8> {
    reply.text.chars().map(|c| c as u8).collect()
}

/// 发起一次 TUP 请求并解码 `tRsp`（`code != 0` -> `SliveError::Api`）。
async fn tup_call<R>(
    site: &HuyaSite,
    servant: &str,
    func: &str,
    req: &impl TarsStruct,
) -> Result<R, SliveError>
where
    R: TarsStruct,
{
    let mut packet = UniPacket::new();
    packet.set_servant_name(servant);
    packet.set_func_name(func);
    packet.set_request_id(0);
    packet.put("tReq", req.encode()?)?;
    let body = packet.encode()?;

    let request = PostBytesRequest {
        url: format!("{}{}", super::common::WUP_URL, super::common::WUP_PATH),
        headers: site.request_headers(),
        body,
    };
    let reply = site.post().post_bytes(&request).await?;
    let response_bytes = reply_bytes(&reply);

    let decoded = UniPacket::decode(&response_bytes)?;
    let code = decoded.result_code();
    if code != 0 {
        // 对齐 Dart `BaseTarsHttp.tupRequest`：非 0 抛 TupResultException，不重试
        return Err(SliveError::Api {
            code,
            message: format!("TUP {func} 返回错误码 {code}"),
        });
    }
    let resp_bytes = decoded
        .resp_bytes()
        .ok_or_else(|| SliveError::decode(format!("TUP {func} 响应缺少 tRsp")))?;
    R::decode(resp_bytes)
}

/// F-08 取流 token（`liveui/getCdnTokenInfoEx`）。
pub(crate) async fn fetch_cdn_token(
    site: &HuyaSite,
    stream_name: &str,
) -> Result<String, SliveError> {
    let req = GetCdnTokenExReq::new(
        stream_name.to_string(),
        anon_user_id(&super::common::random_huya_ua()),
    );
    let resp: GetCdnTokenExResp = tup_call(site, SERVANT_LIVE_UI, FUNC_CDN_TOKEN_EX, &req).await?;
    if resp.s_flv_token.is_empty() {
        return Err(SliveError::decode(format!(
            "取流 token 为空: stream_name={stream_name}"
        )));
    }
    Ok(resp.s_flv_token)
}

/// F-10 醒目留言原始条目（`wupui/getHeadLineMessageBoard`）。
pub(crate) async fn fetch_message_board(
    site: &HuyaSite,
    pid: i64,
) -> Result<GetGameEventMessageBoardRsp, SliveError> {
    let req = GetGameEventMessageBoardReq::new(
        pid,
        anon_user_id(super::common::DEFAULT_HYSDK_UA),
    );
    tup_call(
        site,
        SERVANT_WUP_UI,
        FUNC_HEADLINE_BOARD,
        &req,
    )
    .await
}

/// 构造一条 TUP 响应的字节（测试夹具用）。
///
/// 形态对齐服务端：4 字节总长 + header + `{"" : code}` 参数区 + `tRsp` 结构体。
pub fn build_tup_response<R: TarsStruct>(
    servant: &str,
    func: &str,
    code: i32,
    rsp: Option<&R>,
) -> Result<Vec<u8>, SliveError> {
    let mut packet = UniPacket::new();
    packet.set_servant_name(servant);
    packet.set_func_name(func);

    // "" 键：返回码（对齐 Dart `respPack.get("", 0)`）
    //
    // `""` 键的值是**裸字段表**（单个 tag=0 整型）—— Dart `respPack.get("", 0)`
    // 直接在该字节上 `read(0, 0, false)`，多包一层 STRUCT_BEGIN 会让
    // `result_code()` 读不到而回落 0。
    let mut code_bytes = TarsEncoder::new();
    code_bytes.write_i64(code as i64, 0)?;
    packet.attributes.put_bytes("", code_bytes.into_bytes())?;

    if let Some(rsp) = rsp {
        packet.put("tRsp", rsp.encode()?)?;
    }
    packet.encode()
}

/// 把条目表转成 `name -> bytes` 的辅助（诊断用）。
pub fn attributes_summary(packet: &UniPacket) -> BTreeMap<String, usize> {
    packet
        .attributes
        .new_data
        .iter()
        .map(|(k, v)| (k.clone(), v.len()))
        .collect()
}
