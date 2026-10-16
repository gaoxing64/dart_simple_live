//! 抖音弹幕 protobuf 结构：**手写 `prost::Message`**，对照
//! `simple_live_core/lib/src/platforms/douyin/proto/douyin.proto`。
//!
//! 为何手写（免 protoc/build.rs）：
//! - §4.1 依赖锁定只预置 `prost 0.12`，不引入构建期工具链（NDK 交叉编译更稳）；
//! - Dart 侧 `douyin_danmaku.dart` **只消费两个方法**（`WebcastChatMessage` /
//!   `WebcastRoomUserSeqMessage`）的少数字段，全量 8004 行 pb.dart 迁移既无收益
//!   又扩大出错面。这里只保留**链路必需 + 被消费的字段**，字段号与 proto 逐一对齐
//!   （改号即与服务端不兼容，故每个字段都标注 tag）。
//!
//! 已覆盖的方法名：`WebcastChatMessage`（聊天）/ `WebcastRoomUserSeqMessage`（在线人气）。

/// `PushFrame`：WS 二进制帧的最外层信封（payload 为 gzip 压缩的 `Response`）。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct PushFrame {
    /// 序列号（tag=1）。
    #[prost(uint64, tag = "1")]
    pub seq_id: u64,
    /// 日志 ID（ack 回帧须原样带回，tag=2）。
    #[prost(uint64, tag = "2")]
    pub log_id: u64,
    /// 载荷编码（`gzip` / 无，tag=6）。
    #[prost(string, tag = "6")]
    pub payload_encoding: String,
    /// 载荷类型：`msg` / `hb` / `ack`（tag=7）。
    #[prost(string, tag = "7")]
    pub payload_type: String,
    /// 载荷字节（tag=8）。
    #[prost(bytes = "vec", tag = "8")]
    pub payload: Vec<u8>,
}

/// `HeadersList`：`PushFrame.headersList` 的元素类型。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct HeadersList {
    /// 键（tag=1）。
    #[prost(string, tag = "1")]
    pub key: String,
    /// 值（tag=2）。
    #[prost(string, tag = "2")]
    pub value: String,
}

/// `Response`：解压后的消息信封。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Response {
    /// 消息列表（tag=1）。
    #[prost(message, repeated, tag = "1")]
    pub messages_list: Vec<Message>,
    /// 游标（tag=2）。
    #[prost(string, tag = "2")]
    pub cursor: String,
    /// 拉取间隔（tag=3）。
    #[prost(uint64, tag = "3")]
    pub fetch_interval: u64,
    /// 服务端时间（tag=4）。
    #[prost(uint64, tag = "4")]
    pub now: u64,
    /// 内部扩展串（ack 须回带，tag=5）。
    #[prost(string, tag = "5")]
    pub internal_ext: String,
    /// 是否需要回 ack（tag=9）。
    #[prost(bool, tag = "9")]
    pub need_ack: bool,
    /// 心跳间隔（tag=8）。
    #[prost(uint64, tag = "8")]
    pub heartbeat_duration: u64,
}

/// `Message`：单条业务消息（方法名 + 各自的 protobuf 载荷）。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Message {
    /// 方法名（如 `WebcastChatMessage`，tag=1）。
    #[prost(string, tag = "1")]
    pub method: String,
    /// 载荷字节（按 `method` 决定结构，tag=2）。
    #[prost(bytes = "vec", tag = "2")]
    pub payload: Vec<u8>,
    /// 消息 ID（tag=3）。
    #[prost(int64, tag = "3")]
    pub msg_id: i64,
    /// 消息类型（tag=4）。
    #[prost(int32, tag = "4")]
    pub msg_type: i32,
}

/// `Common`：所有业务消息的公共头（仅保留被消费字段）。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Common {
    /// 方法名（tag=1）。
    #[prost(string, tag = "1")]
    pub method: String,
    /// 消息 ID（tag=2）。
    #[prost(uint64, tag = "2")]
    pub msg_id: u64,
    /// 房间号（tag=3）。
    #[prost(uint64, tag = "3")]
    pub room_id: u64,
    /// 创建时间（毫秒，tag=4）。
    #[prost(uint64, tag = "4")]
    pub create_time: u64,
}

/// `Image`：图片（仅 `urlList`，tag=1）。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Image {
    /// 地址列表（tag=1）。
    #[prost(string, repeated, tag = "1")]
    pub url_list: Vec<String>,
}

/// `PublicAreaCommon`：公开区域公共信息（占位，保留字段号以免误判）。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct PublicAreaCommon {
    /// 用户消费（tag=2）。
    #[prost(uint64, tag = "2")]
    pub user_consume_in_room: u64,
    /// 用户送礼数（tag=3）。
    #[prost(uint64, tag = "3")]
    pub user_send_gift_cnt_in_room: u64,
}

/// `User`：用户（`ChatMessage.user`，取 `nickName`）。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct User {
    /// 用户 ID（tag=1）。
    #[prost(uint64, tag = "1")]
    pub id: u64,
    /// 短 ID（tag=2）。
    #[prost(uint64, tag = "2")]
    pub short_id: u64,
    /// 昵称（tag=3）—— Dart 取 `user.nickName` 作为弹幕用户名。
    #[prost(string, tag = "3")]
    pub nick_name: String,
    /// 头像缩略图（tag=9）。
    #[prost(message, optional, tag = "9")]
    pub avatar_thumb: Option<Image>,
    /// 等级（tag=6）。
    #[prost(uint32, tag = "6")]
    pub level: u32,
}

/// `ChatMessage`：`WebcastChatMessage` 的载荷（取 `content` + `user.nickName`）。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct ChatMessage {
    /// 公共头（tag=1）。
    #[prost(message, optional, tag = "1")]
    pub common: Option<Common>,
    /// 用户（tag=2）。
    #[prost(message, optional, tag = "2")]
    pub user: Option<User>,
    /// 文本内容（tag=3）。
    #[prost(string, tag = "3")]
    pub content: String,
    /// 对发送者可见（tag=4）。
    #[prost(bool, tag = "4")]
    pub visible_to_sender: bool,
    /// 公开区域公共信息（tag=8）。
    #[prost(message, optional, tag = "8")]
    pub public_area_common: Option<PublicAreaCommon>,
    /// 礼物图片（tag=9）。
    #[prost(message, optional, tag = "9")]
    pub gift_image: Option<Image>,
    /// 事件时间（毫秒，tag=15）。
    #[prost(uint64, tag = "15")]
    pub event_time: u64,
}

/// `RoomUserSeqMessageContributor`：在线贡献榜成员（未消费，仅占位）。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct RoomUserSeqMessageContributor {
    /// 分数（tag=1）。
    #[prost(uint64, tag = "1")]
    pub score: u64,
    /// 用户（tag=2）。
    #[prost(message, optional, tag = "2")]
    pub user: Option<User>,
}

/// `RoomUserSeqMessage`：`WebcastRoomUserSeqMessage` 的载荷（Dart 取 `totalUser`，tag=7）。
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct RoomUserSeqMessage {
    /// 公共头（tag=1）。
    #[prost(message, optional, tag = "1")]
    pub common: Option<Common>,
    /// 榜单（tag=2）。
    #[prost(message, repeated, tag = "2")]
    pub ranks_list: Vec<RoomUserSeqMessageContributor>,
    /// 总数（tag=3）。
    #[prost(int64, tag = "3")]
    pub total: i64,
    /// 总用户数（tag=7）—— **Dart 上报的人气值来源**。
    #[prost(int64, tag = "7")]
    pub total_user: i64,
    /// 总用户数字符串形态（tag=8）。
    #[prost(string, tag = "8")]
    pub total_user_str: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use prost::Message as _;

    #[test]
    fn push_frame_roundtrip_keeps_tag_numbers() {
        let frame = PushFrame {
            seq_id: 1,
            log_id: 7_382_735_338_101_328_680,
            payload_encoding: "gzip".to_string(),
            payload_type: "msg".to_string(),
            payload: vec![1, 2, 3],
        };
        let bytes = frame.encode_to_vec();
        let back = PushFrame::decode(bytes.as_slice()).expect("应能解码");
        assert_eq!(back, frame);
        // protobuf tag 字节 = (field_number << 3) | wire_type。
        // `seq_id` 是 field 1 + varint(wire_type 0) -> 0b0000_1000
        assert_eq!(bytes[0], 0b0000_1000, "首字节应编码 field=1, wire=varint");
        assert_eq!(bytes[0] >> 3, 1, "field number 必须是 1（proto tag=1）");
        assert_eq!(bytes[0] & 0b111, 0, "wire type 必须是 varint(0)");
    }

    #[test]
    fn chat_message_reads_content_and_nickname() {
        let chat = ChatMessage {
            content: "你好".to_string(),
            user: Some(User {
                nick_name: "小明".to_string(),
                ..Default::default()
            }),
            ..Default::default()
        };
        let back = ChatMessage::decode(chat.encode_to_vec().as_slice()).expect("应能解码");
        assert_eq!(back.content, "你好");
        assert_eq!(back.user.expect("user 存在").nick_name, "小明");
    }

    #[test]
    fn room_user_seq_exposes_total_user_as_online() {
        let seq = RoomUserSeqMessage {
            total_user: 42,
            ..Default::default()
        };
        let back = RoomUserSeqMessage::decode(seq.encode_to_vec().as_slice()).expect("应能解码");
        assert_eq!(back.total_user, 42, "Dart 上报人气取 totalUser(tag=7)");
        assert_eq!(back.total, 0);
    }

    #[test]
    fn response_decodes_need_ack_and_nested_message() {
        let resp = Response {
            messages_list: vec![Message {
                method: "WebcastChatMessage".to_string(),
                payload: vec![9, 9],
                msg_id: 5,
                msg_type: 1,
            }],
            internal_ext: "ext-1".to_string(),
            need_ack: true,
            ..Default::default()
        };
        let back = Response::decode(resp.encode_to_vec().as_slice()).expect("应能解码");
        assert!(back.need_ack, "needAck 是 ack 分支的判据");
        assert_eq!(back.internal_ext, "ext-1");
        assert_eq!(back.messages_list.len(), 1);
        assert_eq!(back.messages_list[0].method, "WebcastChatMessage");
    }
}
