//! 虎牙取流 token 的 TUP 消息（对照 `tars/get_cdn_token_ex_{req,resp}.dart` 与 `types.dart`（`HuyaUserId`））。
//!
//! 与 [`super::tars_msgs`]（WS 弹幕消息）同属虎牙消息层，**只定义结构**，
//! 编解码由共享模块 [`crate::tars`] 的 [`TarsStruct`] 提供。
//!
//! tag 号照抄 Dart 的 `writeTo` / `readFrom` 顺序 —— **tag 顺序即线上字节序**。

use crate::error::SliveError;
use crate::tars::{TarsDecoder, TarsEncoder, TarsStruct};


/// `HuyaUserId`（对齐 Dart `types.dart`，tag 0..7）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct HuyaUserId {
    /// 用户 uid（匿名登录为 0）。
    pub l_uid: i64,
    /// 设备 guid。
    pub s_guid: String,
    /// 登录 token（匿名为空）。
    pub s_token: String,
    /// 虎牙 UA。
    pub s_huya_ua: String,
    /// cookie（匿名固定串）。
    pub s_cookie: String,
    /// token 类型。
    pub i_token_type: i64,
    /// 设备信息。
    pub s_device_info: String,
    /// qimei。
    pub s_qimei: String,
}

impl TarsStruct for HuyaUserId {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            l_uid: d.read_i64_or(0, 0),
            s_guid: d.read_string_or(1, ""),
            s_token: d.read_string_or(2, ""),
            s_huya_ua: d.read_string_or(3, ""),
            s_cookie: d.read_string_or(4, ""),
            i_token_type: d.read_i64_or(5, 0),
            s_device_info: d.read_string_or(6, ""),
            s_qimei: d.read_string_or(7, ""),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_i64(self.l_uid, 0)?;
        e.write_string(&self.s_guid, 1)?;
        e.write_string(&self.s_token, 2)?;
        e.write_string(&self.s_huya_ua, 3)?;
        e.write_string(&self.s_cookie, 4)?;
        e.write_i64(self.i_token_type, 5)?;
        e.write_string(&self.s_device_info, 6)?;
        e.write_string(&self.s_qimei, 7)?;
        Ok(())
    }
}

/// `GetCdnTokenExReq`（对齐 Dart `tars/get_cdn_token_ex_req.dart`，tag 0..4）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GetCdnTokenExReq {
    /// flv url（匿名取流时留空）。
    pub s_flv_url: String,
    /// 流名（必需）。
    pub s_stream_name: String,
    /// 循环时长。
    pub i_loop_time: i64,
    /// 用户标识。
    pub t_id: HuyaUserId,
    /// appId（对齐 Dart 默认 66）。
    pub i_app_id: i64,
}

impl GetCdnTokenExReq {
    /// 按 Dart 默认值构造（`iAppId = 66`）。
    pub fn new(stream_name: String, t_id: HuyaUserId) -> Self {
        Self {
            s_flv_url: String::new(),
            s_stream_name: stream_name,
            i_loop_time: 0,
            t_id,
            i_app_id: 66,
        }
    }
}

impl Default for GetCdnTokenExReq {
    fn default() -> Self {
        Self::new(String::new(), HuyaUserId::default())
    }
}

impl TarsStruct for GetCdnTokenExReq {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            s_flv_url: d.read_string_or(0, ""),
            s_stream_name: d.read_string_or(1, ""),
            i_loop_time: d.read_i64_or(2, 0),
            t_id: d.read_struct(3, HuyaUserId::read_from)?,
            i_app_id: d.read_i64_or(4, 66),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_string(&self.s_flv_url, 0)?;
        e.write_string(&self.s_stream_name, 1)?;
        e.write_i64(self.i_loop_time, 2)?;
        e.write_struct_begin_at(3)?;
        self.t_id.write_to(e)?;
        e.write_struct_end()?;
        e.write_i64(self.i_app_id, 4)?;
        Ok(())
    }
}

/// `GetCdnTokenExResp`（对齐 Dart `tars/get_cdn_token_ex_resp.dart`，tag 0/1）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct GetCdnTokenExResp {
    /// 取流 token（页面 anticode）。
    pub s_flv_token: String,
    /// 过期时间。
    pub i_expire_time: i64,
}

impl TarsStruct for GetCdnTokenExResp {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            s_flv_token: d.read_string_or(0, ""),
            i_expire_time: d.read_i64_or(1, 0),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_string(&self.s_flv_token, 0)?;
        e.write_i64(self.i_expire_time, 1)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::platforms::huya::danmaku::tars_sc::{
        GameEventMessageBoardInfo, GameEventMessageBoardPanel, GetGameEventMessageBoardRsp,
        MessageUser,
    };

    #[test]
    fn message_board_chain_roundtrips() {
        let rsp = GetGameEventMessageBoardRsp {
            t_message_board_panel: GameEventMessageBoardPanel {
                v_info: vec![GameEventMessageBoardInfo {
                    t_message_user: MessageUser {
                        s_nick: "金主".to_string(),
                        s_avatar: "https://img/f.jpg".to_string(),
                    },
                    s_content: "上头条".to_string(),
                    i_cost: 100,
                    i_total_sec: 60,
                    i_count_down: 30,
                    l_message_id: 9,
                    i_cost_pay: 10000,
                }],
            },
        };
        let bytes = rsp.encode().expect("编码");
        let decoded = GetGameEventMessageBoardRsp::decode(&bytes).expect("解码");
        assert_eq!(decoded.t_message_board_panel.v_info[0].s_content, "上头条");
        assert_eq!(decoded.t_message_board_panel.v_info[0].i_cost_pay, 10000);
    }

}
