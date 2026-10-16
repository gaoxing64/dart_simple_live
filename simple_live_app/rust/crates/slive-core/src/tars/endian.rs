//! 字节序类型与运行时切换（对照 Dart `dart:typed_data.Endian`）。
//!
//! # 与 TARS 编码层的关系（重要，别误用）
//!
//! TARS **字段编码层恒为大端**：Dart `tars_dart/lib/tars/codec/tars_output_stream.dart`
//! 的 `BinaryWriter.writeInt` / `writeDouble` 全部硬编码 `Endian.big`，
//! `tars_input_stream.dart` 的 `BinaryReader.readInt` / `readFloat` 同样硬编码 `Endian.big`。
//! 因此本模块的字节序**不参与** TARS 字段编码，只用于：
//!
//! - [`WriteBuffer`] / [`ReadBuffer`] 这类裸缓冲（[`crate::tars::UniPacket`] 的 4 字节长度前缀
//!   显式走大端，斗鱼 STT 分帧走小端）；
//! - 平台侧自有私有协议的分帧。
//!
//! 换句话说：TARS 字段用 [`Endian::Big`]，平台私有分帧按协议选。

/// 字节序。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Endian {
    /// 大端（网络序）。TARS 字段编码与 `UniPacket` 长度前缀使用此模式。
    #[default]
    Big,
    /// 小端（斗鱼 STT 分帧使用此模式）。
    Little,
}

impl Endian {
    /// 是否为大端。
    #[inline]
    pub fn is_big(self) -> bool {
        matches!(self, Self::Big)
    }

    /// 字节序名称（诊断日志用）。
    #[inline]
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Big => "big",
            Self::Little => "little",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_big() {
        assert_eq!(Endian::default(), Endian::Big);
        assert!(Endian::Big.is_big());
        assert!(!Endian::Little.is_big());
    }

    #[test]
    fn as_str_matches_name() {
        assert_eq!(Endian::Big.as_str(), "big");
        assert_eq!(Endian::Little.as_str(), "little");
    }
}
