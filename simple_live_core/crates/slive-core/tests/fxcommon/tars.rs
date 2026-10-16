//! TARS 最小读取工具（虎牙夹具专用，从 `mod.rs` 拆出以守≤300 行门禁）。
//!
//! 对齐 `simple_live_core/packages/tars_dart/lib/tars/codec/tars_output_stream.dart`
//! 的编码规则：字段头 1 字节 `tag<<4 | type`（`tag == 15` 时续 1 字节），
//! 整数按值域选宽且一律**大端**。
//!
//! 注意：这里只需「跳过」而非「取值」，故不实现 Dart 的 `skipToTag`语义
//! —— 用例只在**单帧顺序消费**的场景使用（`assert_tars_fully_consumable`）。
#![allow(dead_code)]

// =====================================================================
// TARS 最小读取工具（虎牙夹具专用）
// =====================================================================

/// 读 TARS 字段头：低 4 位是类型，高 4 位是 tag；tag==15 时再读 1 字节。
pub fn tars_read_head(b: &[u8], p: &mut usize) -> (u8, u8) {
    let byte = b[*p];
    *p += 1;
    let typ = byte & 15;
    let mut tag = (byte & 0xF0) >> 4;
    if tag == 15 {
        tag = b[*p];
        *p += 1;
    }
    (tag, typ)
}

/// 跳过一个 TARS 值（简化版，覆盖虎牙夹具用到的类型）。
pub fn tars_skip_value(b: &[u8], p: &mut usize, typ: u8) {
    match typ {
        0 => *p += 1,             // BYTE
        1 => *p += 2,             // SHORT
        2 | 4 => *p += 4,         // INT / FLOAT
        3 | 5 => *p += 8,         // LONG / DOUBLE
        6 => {
            let len = b[*p] as usize;
            *p += 1 + len; // STRING1
        }
        7 => {
            let len = u32::from_be_bytes([b[*p], b[*p + 1], b[*p + 2], b[*p + 3]]) as usize;
            *p += 4 + len; // STRING4
        }
        8 | 9 => {
            // MAP / LIST：先读长度，再逐元素跳
            let (_, lt) = tars_read_head(b, p);
            let n = match lt {
                0 => {
                    *p += 1;
                    b[*p - 1] as i64
                }
                1 => {
                    *p += 2;
                    i16::from_be_bytes([b[*p - 2], b[*p - 1]]) as i64
                }
                2 => {
                    *p += 4;
                    i32::from_be_bytes([b[*p - 4], b[*p - 3], b[*p - 2], b[*p - 1]]) as i64
                }
                12 => 0, // ZERO_TAG
                _ => panic!("LIST 长度用了不支持的类型 {lt}"),
            };
            for _ in 0..(n * if typ == 8 { 2 } else { 1 }) {
                let (_, et) = tars_read_head(b, p);
                tars_skip_value(b, p, et);
            }
        }
        10 => {
            // STRUCT_BEGIN：循环到 STRUCT_END(11)
            loop {
                let (_, t) = tars_read_head(b, p);
                if t == 11 {
                    return;
                }
                tars_skip_value(b, p, t);
            }
        }
        13 => {
            // SIMPLE_LIST：内嵌 BYTE 头 + 长度 + 原始字节
            let (_, it) = tars_read_head(b, p);
            assert_eq!(it, 0, "simple_list 内层必须是 BYTE");
            //长度是 tag0 的 int，可能编成 BYTE / SHORT / INT / LONG / ZERO_TAG
            let (_, lt) = tars_read_head(b, p);
            let n: usize = match lt {
                12 => 0,
                0 => {
                    let n = b[*p] as usize;
                    *p += 1;
                    n
                }
                1 => {
                    let n = u16::from_be_bytes([b[*p], b[*p + 1]]) as usize;
                    *p += 2;
                    n
                }
                2 => {
                    let n = u32::from_be_bytes([b[*p], b[*p + 1], b[*p + 2], b[*p + 3]]) as usize;
                    *p += 4;
                    n
                }
                3 => {
                    let mut buf = [0u8; 8];
                    buf.copy_from_slice(&b[*p..*p + 8]);
                    *p += 8;
                    u64::from_be_bytes(buf) as usize
                }
                other => panic!("simple_list 长度用了不支持的类型 {other}"),
            };
            *p += n;
        }
        11 | 12 => {} // STRUCT_END / ZERO_TAG：无实体
        other => panic!("未覆盖的 TARS 类型 {other}"),
    }
}

/// 断言一帧 `WebSocketCommand` 被恰好读完（7 个字段）。
pub fn assert_tars_fully_consumable(bytes: &[u8], stem: &str) {
    let mut p = 0usize;
    for _ in 0..7 {
        let (_, typ) = tars_read_head(bytes, &mut p);
        tars_skip_value(bytes, &mut p, typ);
    }
    assert_eq!(p, bytes.len(), "{stem} 应恰好消费完（{p} != {}）", bytes.len());
}
