//! TARS 常量（对齐 Dart `tars_dart/lib/tars/tup/const.dart`）。

/// 网格 key。
pub const STATUS_GRID_KEY: &str = "STATUS_GRID_KEY";
/// 染色 key。
pub const STATUS_DYED_KEY: &str = "STATUS_DYED_KEY";
/// 网格 code。
pub const STATUS_GRID_CODE: &str = "STATUS_GRID_CODE";
/// 采样 key。
pub const STATUS_SAMPLE_KEY: &str = "STATUS_SAMPLE_KEY";
/// 返回码字段名（TUP `status` 中的键）。
pub const STATUS_RESULT_CODE: &str = "STATUS_RESULT_CODE";
/// 返回描述字段名（TUP `status` 中的键）。
pub const STATUS_RESULT_DESC: &str = "STATUS_RESULT_DESC";
/// 非法 hash code。
pub const INVALID_HASH_CODE: i32 = -1;
/// 非法网格 code。
pub const INVALID_GRID_CODE: i32 = -1;

/// TUP 参数区中「返回码」条目的键（TUP3 下 `""` 键承载返回码，对齐 Dart `respPack.get("", 0)`）。
pub const TUP_RESULT_KEY: &str = "";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn result_code_keys_match_dart() {
        assert_eq!(STATUS_RESULT_CODE, "STATUS_RESULT_CODE");
        assert_eq!(STATUS_RESULT_DESC, "STATUS_RESULT_DESC");
        assert_eq!(TUP_RESULT_KEY, "");
    }

    #[test]
    fn invalid_codes_are_minus_one() {
        assert_eq!(INVALID_HASH_CODE, -1);
        assert_eq!(INVALID_GRID_CODE, -1);
    }
}
