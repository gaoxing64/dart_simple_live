//! 虎牙 TARS「裸字段表」读取辅助（服务端下发形态，无 `STRUCT_BEGIN`/`STRUCT_END` 包裹）。
//!
//! 为什么需要它：虎牙 WS 推送的 `data` 载荷与 TUP 响应里的嵌套结构都是**裸字段表**，
//! 而共享模块 [`crate::tars::TarsStruct::decode`] 要求完整结构体（带包装）。
//! Dart 侧直接在当前流上 `readFrom`（`huya_danmaku.dart` 的 `HYPushMessage.readFrom`），
//! 故此处提供等价的按 tag 定位读取。
//!
//! ⚠️ 实现要点（踩过的坑，勿改）：
//! - 用 `skip_to_tag(tag)` 定位后交给共享 typed 读取，**不要**自己
//!   `read_field_head()` + `skip_field()` —— `skip_field` 会再读一个字段头，整体错位；
//! - `read_list` 的回调拿到的是**元素字段头之前**的位置，元素自带 `STRUCT_BEGIN`，
//!   故回调要先显式吃掉它（`skip_to_tag(0)` 在「当前头就是 tag 0」时不推进游标）。

use crate::error::SliveError;
use crate::tars::TarsDecoder;

/// 读取**裸字段表**中的 `tag` 处整型（Dart `readFrom` 在裸流上按 tag 读）。
///
/// 虎牙服务端下发的 WS 推送载荷是**裸字段表**（无 `STRUCT_BEGIN`/`STRUCT_END` 包裹），
/// 与 [`TarsStruct::decode`]（要求完整结构体）不同。
///
/// ⚠️ 用 `skip_to_tag` 定位后交给共享 typed 读取，**不要**自己
/// `read_field_head()` + `skip_field()` —— `skip_field` 会再读一个字段头，
/// 导致每轮多消费一个头、整体错位（真实帧上表现为「tag 类型不符」）。
pub(super) fn read_bare_i64(bytes: &[u8], tag: i32) -> Result<i64, SliveError> {
    let mut d = TarsDecoder::new(bytes);
    if !d.skip_to_tag(tag)? {
        return Ok(0); // 缺失：与 Dart 的默认 0 一致
    }
    d.read_i64(tag)
}

/// 读取**裸字段表**中的 `tag` 处 bytes 字段（缺失 -> 空）。
pub(super) fn read_bare_bytes(bytes: &[u8], tag: i32) -> Result<Vec<u8>, SliveError> {
    let mut d = TarsDecoder::new(bytes);
    if !d.skip_to_tag(tag)? {
        return Ok(Vec::new());
    }
    d.read_bytes(tag)
}

/// 读取**裸字段表**中的 `tag` 处字符串字段（缺失 -> 空串）。
pub(super) fn read_bare_string(bytes: &[u8], tag: i32) -> Result<String, SliveError> {
    let mut d = TarsDecoder::new(bytes);
    if !d.skip_to_tag(tag)? {
        return Ok(String::new());
    }
    d.read_string(tag)
}

/// 取出**裸字段表**中 `tag` 处嵌套结构体的**内部字段表**（去掉 `STRUCT_BEGIN`/`STRUCT_END`）。
///
/// 嵌套结构体的载荷形态是 `STRUCT_BEGIN + 字段表 + STRUCT_END`，其字段表本身又是裸的，
/// 故切出中间段后递归用 `decode_bare`。
pub(super) fn read_bare_struct_bytes(bytes: &[u8], tag: i32) -> Result<Vec<u8>, SliveError> {
    let mut d = TarsDecoder::new(bytes);
    if !d.skip_to_tag(tag)? {
        return Ok(Vec::new());
    }
    let head = d.read_field_head()?;
    if head.ty != crate::tars::TarsType::StructBegin {
        return Err(SliveError::decode(format!(
            "tag={tag} 期望结构体，实为 {:?}",
            head.ty
        )));
    }
    let start = d.position();
    d.skip_to_struct_end()?;
    let end = d.position();
    bytes
        .get(start..end)
        .map(|slice| slice.to_vec())
        .ok_or_else(|| SliveError::decode("嵌套结构体字节越界"))
}

/// 读取**裸字段表**中 `tag` 处的列表字段（元素形态由回调决定）。
pub(super) fn read_bare_struct_list<T>(
    bytes: &[u8],
    tag: i32,
    read_body: impl FnMut(&mut TarsDecoder<'_>) -> Result<T, SliveError>,
) -> Result<Vec<T>, SliveError> {
    let mut d = TarsDecoder::new(bytes);
    if !d.skip_to_tag(tag)? {
        return Ok(Vec::new());
    }
    d.read_list(tag, read_body)
}
