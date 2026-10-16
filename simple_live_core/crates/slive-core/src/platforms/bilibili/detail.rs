//! F-06 房间详情（两步：getInfoByRoom + getDanmuInfo，对照 `bilibili_site.dart:225-270`）。

use serde_json::Value;

use crate::error::SliveError;
use crate::http::check_api_code;
use crate::models::LiveRoomDetail;
use crate::util::as_i32;

use super::danmaku::args::{BiliBiliDanmakuArgs, DEFAULT_SERVER_HOST};
use super::site::BilibiliSite;
use super::util::text_ptr;
use super::wbi;

const INFO_URL: &str = "https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom";
const DANMU_INFO_URL: &str =
    "https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo";

/// 拉取房间详情（含弹幕参数）。
pub(crate) async fn fetch(site: &BilibiliSite, room_id: &str) -> Result<LiveRoomDetail, SliveError> {
    let info_value = fetch_room_info(site, room_id).await?;
    let real_room_id = text_ptr(&info_value, "/data/room_info/room_id");
    if real_room_id.is_empty() || real_room_id == "null" {
        // AC-23：data=null / 房间不存在 -> 类型化错误，不 panic。
        return Err(SliveError::not_found(format!("房间不存在: {room_id}")));
    }

    let danmu_value = fetch_danmu_info(site, &real_room_id).await?;

    let token = text_ptr(&danmu_value, "/data/token");
    let hosts = crate::util::array_at(&danmu_value, "/data/host_list");
    let server_host = hosts
        .first()
        .map(|h| super::util::text(h, "host"))
        .filter(|h| !h.is_empty())
        .unwrap_or_else(|| DEFAULT_SERVER_HOST.to_string());

    // 登录态一致性：cookie 带 SESSDATA（已登录）但 user_id 未回填（启动竞态 /
    // 账号流程未走 F-20）时，join 声称 uid=0 与登录 cookie 矛盾 → 服务端直接
    // reset 连接（真机抓到）。这里先做一次账号校验回填 mid（对齐 Dart core
    // 登录流程语义，get_account_info 内部完成回填）。
    let cookie = site.cookie();
    if cookie.contains("SESSDATA") && site.user_id() == 0 {
        let credential = serde_json::json!({ "cookie": cookie }).to_string();
        if let Err(e) = super::account::get_account_info(site, &credential).await {
            log::warn!("登录态回填失败（以游客继续）: {e}");
        }
    }

    let args = BiliBiliDanmakuArgs::new(
        real_room_id.parse::<i64>().unwrap_or(0),
        site.user_id(),
        token,
        server_host,
        site.buvid_snapshot().0,
        site.cookie(),
    )
    .to_json()?;

    Ok(LiveRoomDetail {
        room_id: real_room_id,
        title: text_ptr(&info_value, "/data/room_info/title"),
        cover: text_ptr(&info_value, "/data/room_info/cover"),
        user_name: text_ptr(&info_value, "/data/anchor_info/base_info/uname"),
        user_avatar: format!(
            "{}@100w.jpg",
            text_ptr(&info_value, "/data/anchor_info/base_info/face")
        ),
        online: as_i32(info_value.pointer("/data/room_info/online")).unwrap_or(0),
        introduction: Some(text_ptr(&info_value, "/data/room_info/description")),
        notice: Some(String::new()),
        status: as_i32(info_value.pointer("/data/room_info/live_status")).unwrap_or(0) == 1,
        data: None,
        danmaku_data: Some(args),
        is_record: false,
        url: format!("https://live.bilibili.com/{room_id}"),
    })
}

async fn fetch_room_info(site: &BilibiliSite, room_id: &str) -> Result<Value, SliveError> {
    let full = format!("{INFO_URL}?room_id={room_id}");
    let query = wbi::sign(site, &full).await?;
    let value = site.get_json(INFO_URL, query).await?;
    check_api_code(&value)?;
    if value.get("data").map(Value::is_null).unwrap_or(true) {
        return Err(SliveError::not_found(format!("房间不存在: {room_id}")));
    }
    Ok(value)
}

async fn fetch_danmu_info(site: &BilibiliSite, real_room_id: &str) -> Result<Value, SliveError> {
    let full = format!("{DANMU_INFO_URL}?id={real_room_id}");
    let query = wbi::sign(site, &full).await?;
    let value = site.get_json(DANMU_INFO_URL, query).await?;
    check_api_code(&value)?;
    Ok(value)
}
