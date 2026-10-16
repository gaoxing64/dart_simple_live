//! TARS 字段类型与「字段头」编解码（对照 Dart `tars_dart/lib/tars/codec/`）。
//!
//! 字段头规则（`tars_struct.dart::TarsStructType` 与 `tars_output_stream.dart::writeHead`）：
//!
//! ```text
//! tag < 15   : 1 字节 = (tag << 4) | type
//! 15 <= tag < 256 : 2 字节 = (15 << 4) | type，随后 1 字节 tag
//! tag >= 256 : 非法（编码侧报错）
//! ```
//!
//! **结构结束标记**：`STRUCT_END`（type=11）以 tag=0 写出，充当字段表的结束符；
//! `ZERO_TAG`（type=12）表示该 tag 的整数值恰为 0 且不携带任何载荷字节
//! （对齐 Dart `writeByte`：值为 0 时只写头不写值）。

/// TARS 字段类型（枚举序号即线上字节值，与 Dart `TarsStructType` 逐一对齐）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum TarsType {
    /// int1（1 字节）。
    Byte = 0,
    /// int2（2 字节）。
    Short = 1,
    /// int4（4 字节）。
    Int = 2,
    /// int8（8 字节）。
    Long = 3,
    /// float（4 字节）。
    Float = 4,
    /// double（8 字节）。
    Double = 5,
    /// string1（1 字节长度 + 内容）。
    String1 = 6,
    /// string4（4 字节长度 + 内容）。
    String4 = 7,
    /// Map。
    Map = 8,
    /// List。
    List = 9,
    /// 结构开始。
    StructBegin = 10,
    /// 结构结束（tag=0）。
    StructEnd = 11,
    /// 零值标记（无载荷）。
    ZeroTag = 12,
    /// SimpleList（byte 数组）。
    SimpleList = 13,
}

impl TarsType {
    /// 从线上字节值解析；非法值返回 `None`。
    pub fn from_u8(v: u8) -> Option<Self> {
        Some(match v {
            0 => Self::Byte,
            1 => Self::Short,
            2 => Self::Int,
            3 => Self::Long,
            4 => Self::Float,
            5 => Self::Double,
            6 => Self::String1,
            7 => Self::String4,
            8 => Self::Map,
            9 => Self::List,
            10 => Self::StructBegin,
            11 => Self::StructEnd,
            12 => Self::ZeroTag,
            13 => Self::SimpleList,
            _ => return None,
        })
    }

    /// 该类型是否为整型族（`read_i64` 可接受）。
    pub fn is_integral(self) -> bool {
        matches!(
            self,
            Self::Byte | Self::Short | Self::Int | Self::Long | Self::ZeroTag
        )
    }

    /// 该类型是否为浮点族（`read_f64` 可接受）。
    pub fn is_floating(self) -> bool {
        matches!(self, Self::Float | Self::Double | Self::ZeroTag)
    }

    /// 该类型是否为字符串族。
    pub fn is_string(self) -> bool {
        matches!(self, Self::String1 | Self::String4)
    }

    /// 类型名（诊断信息用）。
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Byte => "BYTE",
            Self::Short => "SHORT",
            Self::Int => "INT",
            Self::Long => "LONG",
            Self::Float => "FLOAT",
            Self::Double => "DOUBLE",
            Self::String1 => "STRING1",
            Self::String4 => "STRING4",
            Self::Map => "MAP",
            Self::List => "LIST",
            Self::StructBegin => "STRUCT_BEGIN",
            Self::StructEnd => "STRUCT_END",
            Self::ZeroTag => "ZERO_TAG",
            Self::SimpleList => "SIMPLE_LIST",
        }
    }
}

/// tag 上限：超出则字段头无法表达（对齐 Dart `writeHead` 的 `tag >= 256` 抛错）。
pub const MAX_TAG: i32 = 255;

/// 字段头（tag + type）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FieldHead {
    /// 字段标签。
    pub tag: i32,
    /// 字段类型。
    pub ty: TarsType,
}

impl FieldHead {
    /// 构造。
    pub fn new(tag: i32, ty: TarsType) -> Self {
        Self { tag, ty }
    }
}

/// 写字段头到 `buf`；`tag` 越界返回 `Err`。
pub(crate) fn write_head(buf: &mut Vec<u8>, ty: TarsType, tag: i32) -> Result<(), crate::error::SliveError> {
    if tag < 0 {
        return Err(crate::error::SliveError::invalid_input(format!(
            "TARS tag 不能为负: {tag}"
        )));
    }
    if tag > MAX_TAG {
        return Err(crate::error::SliveError::invalid_input(format!(
            "TARS tag 过大: {tag} > {MAX_TAG}"
        )));
    }
    let t = ty as u8;
    if tag < 15 {
        buf.push(((tag as u8) << 4) | t);
    } else {
        buf.push((15 << 4) | t);
        buf.push(tag as u8);
    }
    Ok(())
}

/// 从 `buf[pos..]` 读字段头，返回 `(FieldHead, 头字节数)`。
pub(crate) fn read_head(
    buf: &[u8],
    pos: usize,
) -> Result<(FieldHead, usize), crate::error::SliveError> {
    if pos >= buf.len() {
        return Err(crate::error::SliveError::decode(
            "TARS 读字段头失败：已读到缓冲区末尾",
        ));
    }
    let b = buf[pos];
    let ty_v = b & 15;
    let tag_hi = (b >> 4) as i32;
    let ty = TarsType::from_u8(ty_v).ok_or_else(|| {
        crate::error::SliveError::decode(format!("TARS 非法字段类型字节: {ty_v}"))
    })?;
    if tag_hi == 15 {
        if pos + 1 >= buf.len() {
            return Err(crate::error::SliveError::decode(
                "TARS 读字段头失败：tag >= 15 但缺少第二字节",
            ));
        }
        Ok((FieldHead::new(buf[pos + 1] as i32, ty), 2))
    } else {
        Ok((FieldHead::new(tag_hi, ty), 1))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn type_values_match_dart_enum_order() {
        // 与 Dart `enum TarsStructType { BYTE, SHORT, INT, LONG, FLOAT, DOUBLE,
        // STRING1, STRING4, MAP, LIST, STRUCT_BEGIN, STRUCT_END, ZERO_TAG, SIMPLE_LIST }` 对齐
        let pairs = [
            (TarsType::Byte, 0u8),
            (TarsType::Short, 1),
            (TarsType::Int, 2),
            (TarsType::Long, 3),
            (TarsType::Float, 4),
            (TarsType::Double, 5),
            (TarsType::String1, 6),
            (TarsType::String4, 7),
            (TarsType::Map, 8),
            (TarsType::List, 9),
            (TarsType::StructBegin, 10),
            (TarsType::StructEnd, 11),
            (TarsType::ZeroTag, 12),
            (TarsType::SimpleList, 13),
        ];
        for (t, v) in pairs {
            assert_eq!(t as u8, v, "{:?} 的字节值应为 {v}", t);
            assert_eq!(TarsType::from_u8(v), Some(t));
        }
        assert_eq!(TarsType::from_u8(14), None);
        assert_eq!(TarsType::from_u8(255), None);
    }

    #[test]
    fn head_one_byte_when_tag_below_15() {
        let mut buf = Vec::new();
        write_head(&mut buf, TarsType::Int, 3).unwrap();
        assert_eq!(buf, vec![0x32], "(3<<4)|2 = 0x32");
        let (h, n) = read_head(&buf, 0).unwrap();
        assert_eq!(h, FieldHead::new(3, TarsType::Int));
        assert_eq!(n, 1);
    }

    #[test]
    fn head_two_bytes_when_tag_from_15_to_255() {
        let mut buf = Vec::new();
        write_head(&mut buf, TarsType::String1, 15).unwrap();
        assert_eq!(buf, vec![0xF6, 15]);
        let (h, n) = read_head(&buf, 0).unwrap();
        assert_eq!(h.tag, 15);
        assert_eq!(h.ty, TarsType::String1);
        assert_eq!(n, 2);

        let mut buf2 = Vec::new();
        write_head(&mut buf2, TarsType::Long, 255).unwrap();
        assert_eq!(buf2, vec![0xF3, 255]);
        assert_eq!(read_head(&buf2, 0).unwrap().0.tag, 255);
    }

    #[test]
    fn tag_zero_struct_end_marker() {
        // STRUCT_END 以 tag=0 写出，是字段表结束符
        let mut buf = Vec::new();
        write_head(&mut buf, TarsType::StructEnd, 0).unwrap();
        assert_eq!(buf, vec![0x0B]);
        assert_eq!(read_head(&buf, 0).unwrap().0.ty, TarsType::StructEnd);
    }

    #[test]
    fn tag_out_of_range_is_error() {
        let mut buf = Vec::new();
        assert!(write_head(&mut buf, TarsType::Int, 256).is_err());
        assert!(write_head(&mut buf, TarsType::Int, -1).is_err());
        assert!(buf.is_empty());
        assert!(write_head(&mut buf, TarsType::Int, MAX_TAG).is_ok());
    }

    #[test]
    fn read_head_on_truncated_input_is_error() {
        assert!(read_head(&[], 0).is_err());
        // tag_hi==15 但缺第二字节
        assert!(read_head(&[0xF6], 0).is_err());
    }

    #[test]
    fn type_predicates_and_names() {
        assert!(TarsType::Byte.is_integral());
        assert!(TarsType::ZeroTag.is_integral());
        assert!(!TarsType::Int.is_floating());
        assert!(TarsType::Double.is_floating());
        assert!(TarsType::String4.is_string());
        assert_eq!(TarsType::SimpleList.as_str(), "SIMPLE_LIST");
        assert_eq!(TarsType::StructBegin.as_str(), "STRUCT_BEGIN");
    }
}
