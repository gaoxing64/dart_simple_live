//! 动态 TARS 值 [`TarsValue`] —— 编码器与结构体字段共用的值表达。
//!
//! 用途：平台侧需要表达嵌套结构（`List` / `Map` / 子结构体）时，
//! 用本枚举即可完成编解码，无需为每个平台消息手写字段读写样板。
//! 简单字段（int / string / bytes）仍建议直接用
//! [`TarsEncoder`](super::TarsEncoder) / [`TarsDecoder`](super::TarsDecoder) 的强类型方法。

/// 可编码 / 解码的动态 TARS 值。
#[derive(Debug, Clone, PartialEq)]
pub enum TarsValue {
    /// 整型（写入时按值域自动选 `BYTE`/`SHORT`/`INT`/`LONG`）。
    Int(i64),
    /// 双精度浮点（写入恒为 `DOUBLE`，对齐 Dart `writeDouble`）。
    Double(f64),
    /// 布尔（写入为 `BYTE`，对齐 Dart `writeBool`）。
    Bool(bool),
    /// 字符串（UTF-8，长度按字节数计）。
    Str(String),
    /// 裸字节（写入为 `SIMPLE_LIST`）。
    Bytes(Vec<u8>),
    /// 列表。
    List(Vec<TarsValue>),
    /// Map 条目序列（保持线上写入顺序）。
    Map(Vec<(TarsValue, TarsValue)>),
    /// 结构体字段表：`Vec<(tag, value)>`，编码时按给定顺序写出并自动补 `STRUCT_END`。
    Struct(Vec<(i32, TarsValue)>),
}

impl TarsValue {
    /// 便捷构造：整型。
    pub fn int(v: impl Into<i64>) -> Self {
        Self::Int(v.into())
    }

    /// 便捷构造：字符串。
    pub fn string(v: impl Into<String>) -> Self {
        Self::Str(v.into())
    }

    /// 便捷构造：字符串（[`TarsValue::string`] 的别名）。
    ///
    /// 与 Dart `TarsValue.Str` 命名对齐，便于平台侧从 Dart 代码逐行迁移时保持可读性。
    pub fn str(v: impl Into<String>) -> Self {
        Self::Str(v.into())
    }

    /// 便捷构造：字节数组。
    pub fn bytes(v: impl Into<Vec<u8>>) -> Self {
        Self::Bytes(v.into())
    }

    /// 便捷构造：浮点。
    pub fn double(v: f64) -> Self {
        Self::Double(v)
    }

    /// 便捷构造：布尔。
    pub fn boolean(v: bool) -> Self {
        Self::Bool(v)
    }

    /// 便捷构造：列表。
    pub fn list(items: Vec<TarsValue>) -> Self {
        Self::List(items)
    }

    /// 便捷构造：Map。
    pub fn map(entries: Vec<(TarsValue, TarsValue)>) -> Self {
        Self::Map(entries)
    }

    /// 便捷构造：结构体字段表。
    pub fn strukt(fields: Vec<(i32, TarsValue)>) -> Self {
        Self::Struct(fields)
    }

    /// 类型名（诊断信息用）。
    pub fn type_name(&self) -> &'static str {
        match self {
            Self::Int(_) => "int",
            Self::Double(_) => "double",
            Self::Bool(_) => "bool",
            Self::Str(_) => "string",
            Self::Bytes(_) => "bytes",
            Self::List(_) => "list",
            Self::Map(_) => "map",
            Self::Struct(_) => "struct",
        }
    }

    /// 取整型值（类型不符返回 `None`）。
    pub fn as_int(&self) -> Option<i64> {
        match self {
            Self::Int(v) => Some(*v),
            _ => None,
        }
    }

    /// 取字符串值（类型不符返回 `None`）。
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Self::Str(v) => Some(v),
            _ => None,
        }
    }

    /// 取字节值（类型不符返回 `None`）。
    pub fn as_bytes(&self) -> Option<&[u8]> {
        match self {
            Self::Bytes(v) => Some(v),
            _ => None,
        }
    }

    /// 取列表引用（类型不符返回 `None`）。
    pub fn as_list(&self) -> Option<&[TarsValue]> {
        match self {
            Self::List(v) => Some(v),
            _ => None,
        }
    }

    /// 取 Map 条目（类型不符返回 `None`）。
    pub fn as_map(&self) -> Option<&[(TarsValue, TarsValue)]> {
        match self {
            Self::Map(v) => Some(v),
            _ => None,
        }
    }

    /// 取结构体字段表（类型不符返回 `None`）。
    pub fn as_struct(&self) -> Option<&[(i32, TarsValue)]> {
        match self {
            Self::Struct(v) => Some(v),
            _ => None,
        }
    }

    /// 取浮点值（类型不符返回 `None`）。
    pub fn as_double(&self) -> Option<f64> {
        match self {
            Self::Double(v) => Some(*v),
            _ => None,
        }
    }

    /// 取布尔值（类型不符返回 `None`）。
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Self::Bool(v) => Some(*v),
            _ => None,
        }
    }
}

impl From<i64> for TarsValue {
    fn from(v: i64) -> Self {
        Self::Int(v)
    }
}
impl From<i32> for TarsValue {
    fn from(v: i32) -> Self {
        Self::Int(v as i64)
    }
}
impl From<u32> for TarsValue {
    fn from(v: u32) -> Self {
        Self::Int(v as i64)
    }
}
impl From<bool> for TarsValue {
    fn from(v: bool) -> Self {
        Self::Bool(v)
    }
}
impl From<f64> for TarsValue {
    fn from(v: f64) -> Self {
        Self::Double(v)
    }
}
impl From<String> for TarsValue {
    fn from(v: String) -> Self {
        Self::Str(v)
    }
}
impl From<&str> for TarsValue {
    fn from(v: &str) -> Self {
        Self::Str(v.to_owned())
    }
}
impl From<Vec<u8>> for TarsValue {
    fn from(v: Vec<u8>) -> Self {
        Self::Bytes(v)
    }
}
impl From<Vec<TarsValue>> for TarsValue {
    fn from(v: Vec<TarsValue>) -> Self {
        Self::List(v)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn constructors_and_accessors() {
        let v = TarsValue::int(7i32);
        assert_eq!(v.as_int(), Some(7));
        assert_eq!(v.type_name(), "int");
        assert_eq!(TarsValue::string("a").as_str(), Some("a"));
        assert_eq!(TarsValue::bytes(vec![1]).as_bytes(), Some(&[1u8][..]));
        assert_eq!(TarsValue::double(1.5).as_double(), Some(1.5));
        assert_eq!(TarsValue::boolean(true).as_bool(), Some(true));
        let l = TarsValue::list(vec![TarsValue::int(1)]);
        assert_eq!(l.as_list().map(|x| x.len()), Some(1));
        let m = TarsValue::map(vec![]);
        assert_eq!(m.as_map().map(|x| x.len()), Some(0));
        let s = TarsValue::strukt(vec![(0, TarsValue::int(1))]);
        assert_eq!(s.as_struct().map(|x| x.len()), Some(1));
    }

    #[test]
    fn wrong_type_accessors_return_none() {
        let v = TarsValue::int(1);
        assert_eq!(v.as_str(), None);
        assert_eq!(v.as_bytes(), None);
        assert_eq!(v.as_list(), None);
        assert_eq!(v.as_map(), None);
        assert_eq!(v.as_struct(), None);
        assert_eq!(v.as_double(), None);
        assert_eq!(v.as_bool(), None);
    }

    #[test]
    fn from_impls_cover_primitives() {
        assert_eq!(TarsValue::from(1i32), TarsValue::Int(1));
        assert_eq!(TarsValue::from(2u32), TarsValue::Int(2));
        assert_eq!(TarsValue::from("x"), TarsValue::Str("x".into()));
        assert_eq!(TarsValue::from(String::from("y")), TarsValue::Str("y".into()));
        assert_eq!(TarsValue::from(vec![1u8]), TarsValue::Bytes(vec![1]));
        assert_eq!(TarsValue::from(false), TarsValue::Bool(false));
        assert_eq!(TarsValue::from(0.5), TarsValue::Double(0.5));
        assert_eq!(TarsValue::from(vec![TarsValue::Int(1)]).type_name(), "list");
    }

    #[test]
    fn type_names_are_stable() {
        assert_eq!(TarsValue::Bool(false).type_name(), "bool");
        assert_eq!(TarsValue::Bytes(vec![]).type_name(), "bytes");
        assert_eq!(TarsValue::Map(vec![]).type_name(), "map");
        assert_eq!(TarsValue::Struct(vec![]).type_name(), "struct");
        assert_eq!(TarsValue::Str(String::new()).type_name(), "string");
        assert_eq!(TarsValue::Double(0.0).type_name(), "double");
    }
}
