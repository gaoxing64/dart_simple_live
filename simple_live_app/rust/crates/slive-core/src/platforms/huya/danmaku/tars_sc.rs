//! 虎牙醒目留言（SC）的 TUP 消息（对照 `tars/get_game_event_message_board_*.dart`）。
//!
//! 与 [`super::tars_msgs`]（WS 弹幕消息）同属虎牙消息层，**只定义结构**，
//! 编解码由共享模块 [`crate::tars`] 的 [`TarsStruct`] 提供。
//!
//! tag 号照抄 Dart 的 `writeTo` / `readFrom` 顺序 —— **tag 顺序即线上字节序**。

use crate::error::SliveError;
use crate::tars::{TarsDecoder, TarsEncoder, TarsStruct, TarsValue};

use super::tars_cdn::HuyaUserId;

/// `MessageUser`（对齐 Dart `types.dart`，tag 1/2）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MessageUser {
    /// 昵称。
    pub s_nick: String,
    /// 头像。
    pub s_avatar: String,
}

impl MessageUser {
    /// 字段表（嵌套结构体的唯一来源）。
    pub(crate) fn to_fields(&self) -> Vec<(i32, TarsValue)> {
        vec![
            (1, TarsValue::string(self.s_nick.clone())),
            (2, TarsValue::string(self.s_avatar.clone())),
        ]
    }
}

impl TarsStruct for MessageUser {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            s_nick: d.read_string_or(1, ""),
            s_avatar: d.read_string_or(2, ""),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        for (tag, value) in self.to_fields() {
            e.write_value(&value, tag)?;
        }
        Ok(())
    }
}

/// `GameEventMessageBoardInfo`（tag 0/1/2/4/5/9/12）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct GameEventMessageBoardInfo {
    /// 用户信息。
    pub t_message_user: MessageUser,
    /// 文案。
    pub s_content: String,
    /// 价格（虎牙币）。
    pub i_cost: i64,
    /// 总时长（秒）。
    pub i_total_sec: i64,
    /// 剩余时长（秒）。
    pub i_count_down: i64,
    /// 消息 id。
    pub l_message_id: i64,
    /// 支付额（分）。
    pub i_cost_pay: i64,
}

impl GameEventMessageBoardInfo {
    /// 字段表（列表元素的唯一来源）。
    pub(crate) fn to_fields(&self) -> Vec<(i32, TarsValue)> {
        vec![
            (0, TarsValue::Struct(self.t_message_user.to_fields())),
            (1, TarsValue::string(self.s_content.clone())),
            (2, TarsValue::int(self.i_cost)),
            (4, TarsValue::int(self.i_total_sec)),
            (5, TarsValue::int(self.i_count_down)),
            (9, TarsValue::int(self.l_message_id)),
            (12, TarsValue::int(self.i_cost_pay)),
        ]
    }
}

impl TarsStruct for GameEventMessageBoardInfo {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            t_message_user: d.read_struct(0, MessageUser::read_from)?,
            s_content: d.read_string_or(1, ""),
            i_cost: d.read_i64_or(2, 0),
            i_total_sec: d.read_i64_or(4, 0),
            i_count_down: d.read_i64_or(5, 0),
            l_message_id: d.read_i64_or(9, 0),
            i_cost_pay: d.read_i64_or(12, 0),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        for (tag, value) in self.to_fields() {
            e.write_value(&value, tag)?;
        }
        Ok(())
    }
}

/// `GameEventMessageBoardPanel`（tag 1）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct GameEventMessageBoardPanel {
    /// 留言列表。
    pub v_info: Vec<GameEventMessageBoardInfo>,
}

impl TarsStruct for GameEventMessageBoardPanel {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        // 元素是完整结构体（Dart `writeList` -> `writeTarsStruct`）
        Ok(Self {
            v_info: d.read_list(1, |inner| {
                inner.read_struct(0, GameEventMessageBoardInfo::read_from)
            })?,
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        let items: Vec<TarsValue> = self
            .v_info
            .iter()
            .map(|item| TarsValue::Struct(item.to_fields()))
            .collect();
        e.write_list(&items, 1)?;
        Ok(())
    }
}

/// `GetGameEventMessageBoardReq`（tag 0..4）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GetGameEventMessageBoardReq {
    /// 房间 pid（= topSid）。
    pub l_pid: i64,
    /// 偏移（Dart 不填）。
    pub s_offset: String,
    /// 用户标识。
    pub t_id: HuyaUserId,
    /// 面板范围（Dart 固定 0）。
    pub i_message_board_scope: i64,
    /// 每页条数（Dart 固定 50）。
    pub i_page_size: i64,
}

impl GetGameEventMessageBoardReq {
    /// 按 Dart 默认值构造（`scope = 0`、`pageSize = 50`）。
    pub fn new(pid: i64, t_id: HuyaUserId) -> Self {
        Self {
            l_pid: pid,
            s_offset: String::new(),
            t_id,
            i_message_board_scope: 0,
            i_page_size: 50,
        }
    }
}

impl Default for GetGameEventMessageBoardReq {
    fn default() -> Self {
        Self::new(0, HuyaUserId::default())
    }
}

impl TarsStruct for GetGameEventMessageBoardReq {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            l_pid: d.read_i64_or(0, 0),
            s_offset: d.read_string_or(1, ""),
            t_id: d.read_struct(2, HuyaUserId::read_from)?,
            i_message_board_scope: d.read_i64_or(3, 0),
            i_page_size: d.read_i64_or(4, 10),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_i64(self.l_pid, 0)?;
        e.write_string(&self.s_offset, 1)?;
        e.write_struct_begin_at(2)?;
        self.t_id.write_to(e)?;
        e.write_struct_end()?;
        e.write_i64(self.i_message_board_scope, 3)?;
        e.write_i64(self.i_page_size, 4)?;
        Ok(())
    }
}

/// `GetGameEventMessageBoardRsp`（tag 1）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct GetGameEventMessageBoardRsp {
    /// 留言面板。
    pub t_message_board_panel: GameEventMessageBoardPanel,
}

impl TarsStruct for GetGameEventMessageBoardRsp {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            t_message_board_panel: d.read_struct(1, GameEventMessageBoardPanel::read_from)?,
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_struct_begin_at(1)?;
        self.t_message_board_panel.write_to(e)?;
        e.write_struct_end()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::platforms::huya::danmaku::tars_cdn::{GetCdnTokenExReq, GetCdnTokenExResp};

    #[test]
    fn cdn_token_req_resp_roundtrip() {
        let req = GetCdnTokenExReq::new(
            "stream1".to_string(),
            HuyaUserId {
                s_huya_ua: "adr&13.1.0&official".to_string(),
                s_guid: "guid".to_string(),
                ..Default::default()
            },
        );
        let bytes = req.encode().expect("编码");
        assert_eq!(GetCdnTokenExReq::decode(&bytes).expect("解码"), req);
        assert_eq!(req.i_app_id, 66, "对齐 Dart 默认 appId");

        let resp = GetCdnTokenExResp {
            s_flv_token: "token-abc".to_string(),
            i_expire_time: 3600,
        };
        let bytes = resp.encode().expect("编码");
        assert_eq!(GetCdnTokenExResp::decode(&bytes).expect("解码"), resp);
    }

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
