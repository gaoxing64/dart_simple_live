//! 虎牙 WS 弹幕 V2 推送的 TARS 消息（对照 `tars/huya_danmaku.dart` 的
//! `WSPushMessage_V2` / `WSMsgItem`）。
//!
//! **只定义结构**，编解码由共享模块 [`crate::tars`] 提供。
//! 与 [`super::tars_msgs`]（cmdType=7 的推送外壳与聊天消息）并列。
//!
//! tag 号照抄 Dart 的 `writeTo` / `readFrom` 顺序 —— **tag 顺序即线上字节序**。

use crate::error::SliveError;
use crate::tars::{TarsDecoder, TarsEncoder, TarsStruct, TarsValue};

use super::bare::{read_bare_bytes, read_bare_i64, read_bare_string, read_bare_struct_list};

// ---------------------------------------------------------------------------
// WS 弹幕：推送 V2（cmdType = 22）
// ---------------------------------------------------------------------------

/// `x.WSMsgItem`（对齐 Dart `WSMsgItem`，tag 0/1/2）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct WsMsgItem {
    /// 消息 uri（`2001317` = 醒目留言事件；2026-10-17 上游同步更正，旧值 2001314）。
    pub i_uri: i64,
    /// 消息体。
    pub s_msg: Vec<u8>,
    /// 消息 id。
    pub l_msg_id: i64,
}

impl WsMsgItem {
    /// 解码**裸字段表**形态（服务端下发形态）。
    pub fn decode_bare(bytes: &[u8]) -> Result<Self, SliveError> {
        Ok(Self {
            i_uri: read_bare_i64(bytes, 0)?,
            s_msg: read_bare_bytes(bytes, 1)?,
            l_msg_id: read_bare_i64(bytes, 2)?,
        })
    }
}

impl WsMsgItem {
    /// `read_list` 回调用：元素是**完整结构体**（`STRUCT_BEGIN` + 字段表 + `STRUCT_END`）。
    ///
    /// ⚠️ 必须先显式吃掉元素头的 `STRUCT_BEGIN`：`skip_to_tag(0)` 在「当前头就是
    /// tag 0」时**不推进游标**，直接 `read_i64(0)` 会把这个 `STRUCT_BEGIN` 当成
    /// 目标字段而报「实为 STRUCT_BEGIN」。
    pub(crate) fn read_from_bare(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        let head = d.read_field_head()?;
        if head.ty != crate::tars::TarsType::StructBegin {
            return Err(SliveError::decode(format!(
                "列表元素期望 STRUCT_BEGIN，实为 {:?}",
                head.ty
            )));
        }
        Ok(Self {
            i_uri: d.read_i64_or(0, 0),
            s_msg: d.read_bytes_or(1),
            l_msg_id: d.read_i64_or(2, 0),
        })
    }

    /// 字段表（列表元素的唯一来源：既用于 `write_to`，也用于 `TarsValue::Struct`）。
    pub(crate) fn to_fields(&self) -> Vec<(i32, TarsValue)> {
        vec![
            (0, TarsValue::int(self.i_uri)),
            (1, TarsValue::bytes(self.s_msg.clone())),
            (2, TarsValue::int(self.l_msg_id)),
        ]
    }
}

impl TarsStruct for WsMsgItem {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            i_uri: d.read_i64_or(0, 0),
            s_msg: d.read_bytes_or(1),
            l_msg_id: d.read_i64_or(2, 0),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        for (tag, value) in self.to_fields() {
            e.write_value(&value, tag)?;
        }
        Ok(())
    }
}

/// `x.WSPushMessage_V2`（对齐 Dart `WSPushMessageV2`，tag 0/1）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct WsPushMessageV2 {
    /// 群组 id。
    pub s_group_id: String,
    /// 消息项列表。
    pub v_msg_item: Vec<WsMsgItem>,
}

impl WsPushMessageV2 {
    /// 解码**裸字段表**形态（服务端下发形态）。
    pub fn decode_bare(bytes: &[u8]) -> Result<Self, SliveError> {
        Ok(Self {
            s_group_id: read_bare_string(bytes, 0)?,
            // 列表元素是裸字段表（外层 `read_list` 已定位到元素字段头之前）
            v_msg_item: read_bare_struct_list(bytes, 1, WsMsgItem::read_from_bare)?,
        })
    }
}

impl TarsStruct for WsPushMessageV2 {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            s_group_id: d.read_string_or(0, ""),
            v_msg_item: d.read_list(1, WsMsgItem::read_from)?,
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_string(&self.s_group_id, 0)?;
        // ⚠️ 列表元素必须是**结构体**（Dart `writeList` -> `writeTarsStruct`）；
        // 用 `Bytes` 会把元素降级成 SIMPLE_LIST，服务端与回验器都不认。
        let items: Vec<TarsValue> = self
            .v_msg_item
            .iter()
            .map(|item| TarsValue::Struct(item.to_fields()))
            .collect();
        e.write_list(&items, 1)?;
        Ok(())
    }
}
