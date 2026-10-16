//! 虎牙 WS 弹幕的 TARS 消息定义（对照 `platforms/huya/tars/huya_danmaku.dart`）。
//!
//! **本模块只放虎牙自己的消息定义**，TARS 基础层（字节序 / buffer / 字段头 /
//! typed 编解码 / `UniPacket`）由共享模块 [`crate::tars`] 提供，此处不重复实现 ——
//! 每个消息只需实现 [`TarsStruct`] 的 `read_from` / `write_to`。
//!
//! 覆盖：推送外壳（`cmdType=7`）、推送 V2（`cmdType=22`）、聊天消息（`uri=1400`）。
//! TUP HTTP 的消息在 [`super::tars_tup`]。
//!
//! tag 号一律照抄 Dart 的 `writeTo` / `readFrom` 顺序 —— **tag 顺序即线上字节序，改动即破协议**。

use crate::error::SliveError;
use crate::tars::{TarsDecoder, TarsEncoder, TarsStruct};

use super::bare::{read_bare_bytes, read_bare_i64, read_bare_string, read_bare_struct_bytes};

// ---------------------------------------------------------------------------
// WS 弹幕：推送外壳
// ---------------------------------------------------------------------------

/// `x.PuShMessage`（对齐 Dart `HYPushMessage`，tag 0..3）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct HyPushMessage {
    /// 推送类型。
    pub push_type: i64,
    /// 消息 uri（1400 = 聊天，8006 = 人气）。
    pub uri: i64,
    /// 消息体（内层 TARS 字节）。
    pub msg: Vec<u8>,
    /// 协议类型。
    pub protocol_type: i64,
}

impl HyPushMessage {
    /// 解码**裸字段表**形态（服务端下发形态；无 STRUCT_BEGIN/END）。
    pub fn decode_bare(bytes: &[u8]) -> Result<Self, SliveError> {
        Ok(Self {
            push_type: read_bare_i64(bytes, 0)?,
            uri: read_bare_i64(bytes, 1)?,
            msg: read_bare_bytes(bytes, 2)?,
            protocol_type: read_bare_i64(bytes, 3)?,
        })
    }
}

impl TarsStruct for HyPushMessage {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            push_type: d.read_i64_or(0, 0),
            uri: d.read_i64_or(1, 0),
            msg: d.read_bytes_or(2),
            protocol_type: d.read_i64_or(3, 0),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_i64(self.push_type, 0)?;
        e.write_i64(self.uri, 1)?;
        e.write_bytes(&self.msg, 2)?;
        e.write_i64(self.protocol_type, 3)?;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// WS 弹幕：uri = 1400（聊天）
// ---------------------------------------------------------------------------

/// `x.Sender`（对齐 Dart `HYSender`，注意 **tag 6 缺位**，从 5 直接跳到 7）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct HySender {
    /// 用户 uid。
    pub l_uid: i64,
    /// imid。
    pub l_imid: i64,
    /// 昵称（弹幕 `userName` 来源）。
    pub s_nick_name: String,
    /// 性别。
    pub i_gender: i64,
    /// 头像。
    pub s_avatar_url: String,
    /// 贵族等级。
    pub i_noble_level: i64,
    /// guid。
    pub s_guid: String,
    /// 虎牙 UA。
    pub s_huya_ua: String,
    /// 用户类型。
    pub i_user_type: i64,
}

impl HySender {
    /// 解码**裸字段表**形态（服务端下发形态）。
    pub fn decode_bare(bytes: &[u8]) -> Result<Self, SliveError> {
        Ok(Self {
            l_uid: read_bare_i64(bytes, 0)?,
            l_imid: read_bare_i64(bytes, 1)?,
            s_nick_name: read_bare_string(bytes, 2)?,
            i_gender: read_bare_i64(bytes, 3)?,
            s_avatar_url: read_bare_string(bytes, 4)?,
            i_noble_level: read_bare_i64(bytes, 5)?,
            s_guid: read_bare_string(bytes, 7)?,
            s_huya_ua: read_bare_string(bytes, 8)?,
            i_user_type: read_bare_i64(bytes, 9)?,
        })
    }
}

impl TarsStruct for HySender {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            l_uid: d.read_i64_or(0, 0),
            l_imid: d.read_i64_or(1, 0),
            s_nick_name: d.read_string_or(2, ""),
            i_gender: d.read_i64_or(3, 0),
            s_avatar_url: d.read_string_or(4, ""),
            i_noble_level: d.read_i64_or(5, 0),
            s_guid: d.read_string_or(7, ""),
            s_huya_ua: d.read_string_or(8, ""),
            i_user_type: d.read_i64_or(9, 0),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_i64(self.l_uid, 0)?;
        e.write_i64(self.l_imid, 1)?;
        e.write_string(&self.s_nick_name, 2)?;
        e.write_i64(self.i_gender, 3)?;
        e.write_string(&self.s_avatar_url, 4)?;
        e.write_i64(self.i_noble_level, 5)?;
        // tag 6 在 Dart 中不存在，必须跳过
        e.write_string(&self.s_guid, 7)?;
        e.write_string(&self.s_huya_ua, 8)?;
        e.write_i64(self.i_user_type, 9)?;
        Ok(())
    }
}

/// `x.BulletFormat`（对齐 Dart `HYBulletFormat`，tag 0..3）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HyBulletFormat {
    /// 字体颜色（十进制 RGB；`<= 0` 由上层按白色处理）。
    pub font_color: i64,
    /// 字号。
    pub font_size: i64,
    /// 滚动速度。
    pub text_speed: i64,
    /// 特效类型。
    pub transition_type: i64,
}

impl Default for HyBulletFormat {
    fn default() -> Self {
        Self {
            font_color: 0,
            // 对齐 Dart 默认值 fontSize = 4
            font_size: 4,
            text_speed: 0,
            transition_type: 1,
        }
    }
}

impl HyBulletFormat {
    /// 解码**裸字段表**形态（服务端下发形态）。
    pub fn decode_bare(bytes: &[u8]) -> Result<Self, SliveError> {
        Ok(Self {
            font_color: read_bare_i64(bytes, 0)?,
            font_size: read_bare_i64(bytes, 1)?,
            text_speed: read_bare_i64(bytes, 2)?,
            transition_type: read_bare_i64(bytes, 3)?,
        })
    }
}

impl TarsStruct for HyBulletFormat {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            font_color: d.read_i64_or(0, 0),
            font_size: d.read_i64_or(1, 4),
            text_speed: d.read_i64_or(2, 0),
            transition_type: d.read_i64_or(3, 1),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_i64(self.font_color, 0)?;
        e.write_i64(self.font_size, 1)?;
        e.write_i64(self.text_speed, 2)?;
        e.write_i64(self.transition_type, 3)?;
        Ok(())
    }
}

/// `x.Message`（对齐 Dart `HYMessage`，tag 0/3/6）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct HyMessage {
    /// 发送者信息。
    pub user_info: HySender,
    /// 正文。
    pub content: String,
    /// 弹幕样式。
    pub bullet_format: HyBulletFormat,
}

impl HyMessage {
    /// 解码**裸字段表**形态（服务端下发形态）。
    ///
    /// ⚠️ tag 0（`userInfo`）与 tag 6（`bulletFormat`）是**嵌套结构体**：
    /// 载荷形如 `STRUCT_BEGIN + 字段表 + STRUCT_END`，切掉外层后字段表本身是裸的，
    /// 故递归用 `decode_bare`。
    pub fn decode_bare(bytes: &[u8]) -> Result<Self, SliveError> {
        Ok(Self {
            user_info: HySender::decode_bare(&read_bare_struct_bytes(bytes, 0)?)?,
            content: read_bare_string(bytes, 3)?,
            bullet_format: HyBulletFormat::decode_bare(&read_bare_struct_bytes(bytes, 6)?)?,
        })
    }
}

impl TarsStruct for HyMessage {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            user_info: d.read_struct(0, HySender::read_from)?,
            content: d.read_string_or(3, ""),
            bullet_format: d.read_struct(6, HyBulletFormat::read_from)?,
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        // tag 0 = userInfo（嵌套结构体，必须自带 BEGIN/END —— 漏掉 END 会让
        // 后续字段被吞进结构体，解码直接读到缓冲区末尾）
        e.write_struct_begin_at(0)?;
        self.user_info.write_to(e)?;
        e.write_struct_end()?;
        e.write_string(&self.content, 3)?;
        // tag 6 = bulletFormat（同为嵌套结构体）
        e.write_struct_begin_at(6)?;
        self.bullet_format.write_to(e)?;
        e.write_struct_end()?;
        Ok(())
    }
}
