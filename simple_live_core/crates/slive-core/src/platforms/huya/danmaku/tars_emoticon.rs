//! 虎牙表情包 TUP 消息（`wupui/getExpressionEmoticonPackage`）。
//!
//! 结构与字段号对照网页端 `huya-comment` 包的 `HUYA.GetExpressionEmoticonPackage*`：
//! - 请求：`tId(0)` / `lPid(1)` / `iGid(2)` / `iSceneType(3)`；
//! - 响应：`sMessage(0)` / `vPackage(1)` / `vAvailable(2)`；
//! - 包：`sPackageId(0)` / `sName(1)` / `iType(2)` / `sCoverUrl(3)` / `vEmoticon(4)` /
//!   `vUnavailEmoticon(5)` / `iIsLocked(6)` / `sLockedMsg(7)` / `vUnDisplayableId(8)`；
//! - 表情：`sId(0)` / `sName(1)` / `sEscape(2)` / `sUrl(3)` / `sExtraUrl(4)` /
//!   `iType(5)` / `iFrameSize(6)` / `sFlexiUrl(7)` / `iPrice(8)` /
//!   `sExtraFlexiUrl(9)` / `lPackageId(10)`。
//!
//! 只解码消费的字段；未消费的列表字段（`vUnavailEmoticon` 等）保留 tag 号说明，
//! 不参与结构体，避免把无关的大列表搬进内存。

use crate::error::SliveError;
use crate::tars::{TarsDecoder, TarsEncoder, TarsStruct, TarsValue};

use super::tars_cdn::HuyaUserId;

/// `GetExpressionEmoticonPackageReq`（tag 0..3）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GetExpressionEmoticonPackageReq {
    /// 用户标识。
    pub t_id: HuyaUserId,
    /// 房间/主播 pid（`topSid`；为 0 时只返回全局包）。
    pub l_pid: i64,
    /// 频道/公会 id（网页端默认 0）。
    pub i_gid: i64,
    /// 场景类型（网页端固定 1）。
    pub i_scene_type: i64,
}

impl GetExpressionEmoticonPackageReq {
    /// 按网页端默认值构造：`iGid = 0`、`iSceneType = 1`。
    pub fn new(t_id: HuyaUserId, l_pid: i64) -> Self {
        Self {
            t_id,
            l_pid,
            i_gid: 0,
            i_scene_type: 1,
        }
    }
}

impl Default for GetExpressionEmoticonPackageReq {
    fn default() -> Self {
        Self::new(HuyaUserId::default(), 0)
    }
}

impl TarsStruct for GetExpressionEmoticonPackageReq {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            t_id: d.read_struct(0, HuyaUserId::read_from)?,
            l_pid: d.read_i64_or(1, 0),
            i_gid: d.read_i64_or(2, 0),
            i_scene_type: d.read_i64_or(3, 0),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_struct_begin_at(0)?;
        self.t_id.write_to(e)?;
        e.write_struct_end()?;
        e.write_i64(self.l_pid, 1)?;
        e.write_i64(self.i_gid, 2)?;
        e.write_i64(self.i_scene_type, 3)?;
        Ok(())
    }
}

/// `GetExpressionEmoticonPackageRsp`（只消费 `sMessage` + `vPackage`）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct GetExpressionEmoticonPackageRsp {
    /// 服务端提示。
    pub s_message: String,
    /// 表情包列表。
    pub v_package: Vec<ExpressionEmoticonPackage>,
}

impl TarsStruct for GetExpressionEmoticonPackageRsp {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            s_message: d.read_string_or(0, ""),
            v_package: d.read_list(1, |inner| {
                inner.read_struct(0, ExpressionEmoticonPackage::read_from)
            })?,
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_string(&self.s_message, 0)?;
        let items: Vec<TarsValue> = self
            .v_package
            .iter()
            .map(|p| TarsValue::Struct(p.to_fields()))
            .collect();
        e.write_list(&items, 1)?;
        // vAvailable(2) 未消费，不写
        Ok(())
    }
}

/// `ExpressionEmoticonPackage`（只消费展示所需字段）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ExpressionEmoticonPackage {
    /// 包 id。
    pub s_package_id: String,
    /// 包名（`梗表情` / `itai大表情` 等）。
    pub s_name: String,
    /// 包类型：0 = 静态小表情，2 = 梗表情，3 = 大表情。
    pub i_type: i64,
    /// 封面。
    pub s_cover_url: String,
    /// 表情列表。
    pub v_emoticon: Vec<ExpressionEmoticon>,
    /// 是否锁定（1 = 未解锁）。
    pub i_is_locked: i64,
    /// 锁定提示。
    pub s_locked_msg: String,
}

impl ExpressionEmoticonPackage {
    fn to_fields(&self) -> Vec<(i32, TarsValue)> {
        let emoticons: Vec<TarsValue> = self
            .v_emoticon
            .iter()
            .map(|e| TarsValue::Struct(e.to_fields()))
            .collect();
        vec![
            (0, TarsValue::string(self.s_package_id.clone())),
            (1, TarsValue::string(self.s_name.clone())),
            (2, TarsValue::int(self.i_type)),
            (3, TarsValue::string(self.s_cover_url.clone())),
            (4, TarsValue::List(emoticons)),
            (6, TarsValue::int(self.i_is_locked)),
            (7, TarsValue::string(self.s_locked_msg.clone())),
        ]
    }
}

impl TarsStruct for ExpressionEmoticonPackage {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        let s_package_id = d.read_string_or(0, "");
        let s_name = d.read_string_or(1, "");
        let i_type = d.read_i64_or(2, 0);
        let s_cover_url = d.read_string_or(3, "");
        // vEmoticon 缺失 / 元素损坏时保留该包但空列表：一个锁定包或未来变体
        // 不能把整份响应（以及房间其他包）一起丢掉。
        let mut v_emoticon = Vec::new();
        let mut probe = d.clone();
        if let Ok(list) = probe.read_list(4, |inner| {
            inner.read_struct(0, ExpressionEmoticon::read_from)
        }) {
            *d = probe;
            v_emoticon = list;
        }
        let i_is_locked = d.read_i64_or(6, 0);
        let s_locked_msg = d.read_string_or(7, "");
        Ok(Self {
            s_package_id,
            s_name,
            i_type,
            s_cover_url,
            v_emoticon,
            i_is_locked,
            s_locked_msg,
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        for (tag, value) in self.to_fields() {
            e.write_value(&value, tag)?;
        }
        Ok(())
    }
}

/// `ExpressionEmoticon`（展示所需字段）。
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ExpressionEmoticon {
    /// 表情 id。
    pub s_id: String,
    /// 文本码（如 `[墨镜小哥]`）。
    pub s_name: String,
    /// 发送用的 escape（如 `/{mjxg`）。
    pub s_escape: String,
    /// 静态图片地址（type=0 时有值）。
    pub s_url: String,
    /// 静态动态图地址（type=0 动态表情时有值）。
    pub s_extra_url: String,
    /// 表情类型（0/2/3）。
    pub i_type: i64,
    /// 动画帧数（0 = 非动画）。
    pub i_frame_size: i64,
    /// 大表情素材地址（`steam.png`；实际大图见 [`super::emoticon::large_flexi_url`]）。
    pub s_flexi_url: String,
    /// 价格。
    pub i_price: i64,
    /// 动态大表情素材地址。
    pub s_extra_flexi_url: String,
    /// 所属包 id。
    pub l_package_id: i64,
}

impl ExpressionEmoticon {
    fn to_fields(&self) -> Vec<(i32, TarsValue)> {
        vec![
            (0, TarsValue::string(self.s_id.clone())),
            (1, TarsValue::string(self.s_name.clone())),
            (2, TarsValue::string(self.s_escape.clone())),
            (3, TarsValue::string(self.s_url.clone())),
            (4, TarsValue::string(self.s_extra_url.clone())),
            (5, TarsValue::int(self.i_type)),
            (6, TarsValue::int(self.i_frame_size)),
            (7, TarsValue::string(self.s_flexi_url.clone())),
            (8, TarsValue::int(self.i_price)),
            (9, TarsValue::string(self.s_extra_flexi_url.clone())),
            (10, TarsValue::int(self.l_package_id)),
        ]
    }
}

impl TarsStruct for ExpressionEmoticon {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            s_id: d.read_string_or(0, ""),
            s_name: d.read_string_or(1, ""),
            s_escape: d.read_string_or(2, ""),
            s_url: d.read_string_or(3, ""),
            s_extra_url: d.read_string_or(4, ""),
            i_type: d.read_i64_or(5, 0),
            i_frame_size: d.read_i64_or(6, 0),
            s_flexi_url: d.read_string_or(7, ""),
            i_price: d.read_i64_or(8, 0),
            s_extra_flexi_url: d.read_string_or(9, ""),
            l_package_id: d.read_i64_or(10, 0),
        })
    }

    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        for (tag, value) in self.to_fields() {
            e.write_value(&value, tag)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_rsp() -> GetExpressionEmoticonPackageRsp {
        GetExpressionEmoticonPackageRsp {
            s_message: String::new(),
            v_package: vec![ExpressionEmoticonPackage {
                s_package_id: "571".into(),
                s_name: "itai大表情".into(),
                i_type: 3,
                s_cover_url: "https://cover".into(),
                v_emoticon: vec![ExpressionEmoticon {
                    s_id: "4969".into(),
                    s_name: "[墨镜小哥]".into(),
                    s_escape: "/{mjxg".into(),
                    s_flexi_url: "https://fileserver.cdn.huya.com/abc/expressconfig/steam.png"
                        .into(),
                    i_type: 3,
                    l_package_id: 1029,
                    ..Default::default()
                }],
                i_is_locked: 0,
                s_locked_msg: String::new(),
            }],
        }
    }

    #[test]
    fn response_roundtrip_keeps_packages_and_codes() {
        let rsp = sample_rsp();
        let encoded = rsp.encode().expect("编码");
        let back = GetExpressionEmoticonPackageRsp::decode(&encoded).expect("解码");
        assert_eq!(back, rsp);
        assert_eq!(back.v_package[0].v_emoticon[0].s_name, "[墨镜小哥]");
    }

    #[test]
    fn skips_package_without_emoticon_list() {
        use crate::tars::{TarsEncoder, TarsValue};

        let bad = TarsValue::Struct(vec![
            (0, TarsValue::string("bad")),
            (1, TarsValue::string("坏包")),
            (2, TarsValue::int(2)),
            (6, TarsValue::int(0)),
            (7, TarsValue::string("")),
        ]);
        let emoticon = TarsValue::Struct(vec![
            (0, TarsValue::string("1")),
            (1, TarsValue::string("[墨镜小哥]")),
            (2, TarsValue::string("/{mjxg")),
            (5, TarsValue::int(3)),
            (7, TarsValue::string("https://x/steam.png")),
            (10, TarsValue::int(571)),
        ]);
        let good = TarsValue::Struct(vec![
            (0, TarsValue::string("571")),
            (1, TarsValue::string("itai大表情")),
            (2, TarsValue::int(3)),
            (4, TarsValue::List(vec![emoticon])),
        ]);
        let response = TarsValue::Struct(vec![
            (0, TarsValue::string("")),
            (1, TarsValue::List(vec![bad, good])),
        ]);
        let mut encoder = TarsEncoder::new();
        encoder.write_value(&response, 0).expect("response");
        let rsp = GetExpressionEmoticonPackageRsp::decode(&encoder.into_bytes())
            .expect("坏包不应丢弃整份响应");
        assert_eq!(rsp.v_package.len(), 2, "坏包保留但列表为空");
        assert_eq!(rsp.v_package[0].s_package_id, "bad");
        assert!(rsp.v_package[0].v_emoticon.is_empty());
        assert_eq!(rsp.v_package[1].s_package_id, "571");
        assert_eq!(rsp.v_package[1].v_emoticon[0].s_name, "[墨镜小哥]");
    }

    #[test]
    fn request_roundtrip_keeps_room_pid() {
        let req = GetExpressionEmoticonPackageReq::new(
            HuyaUserId {
                s_huya_ua: "webh5&1.0.0&huya".into(),
                ..Default::default()
            },
            1199517808234,
        );
        let encoded = req.encode().expect("编码");
        let back = GetExpressionEmoticonPackageReq::decode(&encoded).expect("解码");
        assert_eq!(back, req);
        assert_eq!(back.l_pid, 1199517808234);
        assert_eq!(back.i_scene_type, 1);
    }
}
