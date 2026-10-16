# 17 - TARS 编解码模块（`crate::tars`）

> 状态：已实现，测试通过。行为基准为 Dart `simple_live_core/packages/tars_dart/lib/tars/`。
> 消费者：`platforms/huya`（TARS over WSS + TUP over HTTP）。

## 1. 定位与边界

`crate::tars` 是**共享基础层**，只做 TARS 线格式的编解码，不含任何平台业务语义。

依赖方向（单向向下，`platforms` 不得被 `tars` 引用）：

```text
platforms/huya ─┐
                ├─> crate::tars ─> crate::error
platforms/douyu ─┘
```

不依赖 `http` / `ws` / `models` / `platforms`，因此可被任意前端壳（Flutter/FRB、Tauri）复用。

### 为什么手写而不用 `tars-stream`

`crates.io` 的 `tars-stream 0.1.1` 依赖 nightly（`#![feature(specialization)]`），stable 编不过且已弃用。
故照 Dart `tars_dart` 手写，`Cargo.toml` **未新增任何依赖**（复用既有 `thiserror` / `serde`）。

## 2. 文件结构

| 文件 | 职责 | 对应 Dart |
|------|------|--------|
| `tars/mod.rs` | 模块出口 + `TarsStruct` trait + `TarsEncoder` 标记头扩展 | —（对齐抽象 `TarsStruct`） |
| `tars/endian.rs` | `Endian` 类型与运行时切换 | `dart:typed_data.Endian` |
| `tars/buffer.rs` | 缓冲共享工具（字节序换算、长度校验、UTF-8 校验） | — |
| `tars/buffer/writer.rs` | `WriteBuffer` 顺序写缓冲 | `tup/write_buffer.dart` `WriteBuffer` |
| `tars/buffer/reader.rs` | `ReadBuffer` 顺序读缓冲（零拷贝） | `tup/write_buffer.dart` `ReadBuffer` |
| `tars/buffer/reader_tests.rs` | `ReadBuffer` 单元测试（外置，满足 300 行门禁） | — |
| `tars/stream.rs` | `TarsType` / `FieldHead` / 字段头编解码 | `codec/tars_struct.dart` + `writeHead`/`readBinaryReaderHead` |
| `tars/encoder.rs` | `TarsEncoder` 值编码引擎 | `codec/tars_output_stream.dart` |
| `tars/decoder.rs` | `TarsDecoder` 字节层解码（定位/跳字段） | `codec/tars_input_stream.dart` |
| `tars/decoder_read.rs` | 强类型字段读取扩展 | `TarsInputStream.read<T>` 系列 |
| `tars/value.rs` | `TarsValue` 动态值枚举 | —（Dart 依赖 `dynamic`） |
| `tars/packet.rs` | `RequestPacket` / `TarsMessage` | `tup/request_packet.dart`、`tup/tars_message.dart` |
| `tars/packet_tests.rs` | `packet.rs` 单元测试（外置） | — |
| `tars/uni_attribute.rs` | `UniAttribute` TUP 字段容器 | `tup/uni_attribute.dart` |
| `tars/uni_packet.rs` | `UniPacket` TUP 封包 | `tup/uni_packet.dart`、`tup/tars_uni_packet.dart` |
| `tars/consts.rs` | 协议常量与返回码键名 | `tup/const.dart` |

全部单文件 <= 300 行（门禁：`find crates/slive-core/src/tars -name '*.rs' | xargs wc -l | awk '$1>300'`，无输出）。
精确行数见 `docs/rust-core/evidence-tars-build-test.log` §1。

## 3. 线格式速查

### 3.1 字段头

```text
tag < 15        : 1 字节  = (tag << 4) | type
15 <= tag < 256 : 2 字节  = (15 << 4) | type，随后 1 字节 tag
tag > 255       : 非法（编码侧返回 Err）
```

### 3.2 类型枚举（`TarsType`，枚举序即线上字节值）

| 字节 | 变体 | 载荷 |
|------|------|------|
| 0 | `Byte` | 1 字节 |
| 1 | `Short` | 2 字节大端 |
| 2 | `Int` | 4 字节大端 |
| 3 | `Long` | 8 字节大端 |
| 4 | `Float` | 4 字节大端 |
| 5 | `Double` | 8 字节大端 |
| 6 | `String1` | 1 字节长度 + UTF-8 |
| 7 | `String4` | 4 字节长度 + UTF-8 |
| 8 | `Map` | 条数 + (key tag=0, value tag=1) 交替 |
| 9 | `List` | 条数 + 元素（元素 tag 恒 0） |
| 10 | `StructBegin` | 结构体开始 |
| 11 | `StructEnd` | **结构体结束标记（tag 恒 0）** |
| 12 | `ZeroTag` | **零值标记，无载荷字节** |
| 13 | `SimpleList` | 内层 `Byte` 头 + 长度 + 数据 |

### 3.3 关键编码规则（逐条对齐 Dart）

| 场景 | Dart | 本模块 |
|------|------|--------|
| 整型选宽 | `writeInt` 按值域选 BYTE/SHORT/INT/LONG | `write_i64` 同 |
| 整值为 0 | 只写 `ZERO_TAG` 头，无载荷 | 同（`write_i64(0, tag)` 产出 1 字节） |
| 空字符串 | `STRING1` + 长度 0 | 同 |
| 字符串长度 | 按 **UTF-8 字节数**（非 char 数）；>255 转 `STRING4` | 同 |
| bytes | `SIMPLE_LIST` 头 + `Byte` 头(tag=0) + 长度 + 数据 | `write_bytes` 同 |
| 结构体 | `STRUCT_BEGIN` + 字段 + `STRUCT_END`(tag=0) | `TarsStruct::encode` 同 |
| 长度字段 | 长度自身也带完整字段头（tag=0 的整型） | 同 |
| `UniPacket` 头 | `putInt32(body.len() + 4, Endian.big)` | `encode()` 同 |

> 整数/浮点载荷**恒为大端**（Dart `BinaryWriter` 硬编码 `Endian.big`）。
> `Endian` 只作用于 `WriteBuffer`/`ReadBuffer` 裸缓冲（如平台私有分帧）。

## 4. 公开 API

### 4.1 定义平台消息：实现 `TarsStruct`

```rust
use slive_core::error::SliveError;
use slive_core::tars::{TarsDecoder, TarsEncoder, TarsStruct};

struct HyPushMessage {
    push_type: i32,
    uri: i32,
    msg: Vec<u8>,
    protocol_type: i32,
}

impl TarsStruct for HyPushMessage {
    fn read_from(d: &mut TarsDecoder<'_>) -> Result<Self, SliveError> {
        Ok(Self {
            push_type: d.read_i64_or(0, 0) as i32,
            uri:      d.read_i64_or(1, 0) as i32,
            msg:      d.read_bytes_or(2),
            protocol_type: d.read_i64_or(3, 0) as i32,
        })
    }
    fn write_to(&self, e: &mut TarsEncoder) -> Result<(), SliveError> {
        e.write_i64(self.push_type as i64, 0)?;
        e.write_i64(self.uri as i64, 1)?;
        e.write_bytes(&self.msg, 2)?;
        e.write_i64(self.protocol_type as i64, 3)?;
        Ok(())
    }
}
```

`TarsStruct` 三个方法：

| 方法 | 说明 |
|------|------|
| `read_from(&mut TarsDecoder)` | 读字段（调用方已定位到 `STRUCT_BEGIN` 之后） |
| `write_to(&mut TarsEncoder)` | 写字段（**不含** `STRUCT_BEGIN`/`STRUCT_END`） |
| `encode() -> Result<Vec<u8>>` | 默认方法：补首尾标记，产出完整结构体字节 |
| `decode(&[u8]) -> Result<Self>` | 默认方法：解析完整结构体字节（**期望输入以 `STRUCT_BEGIN` 开头**） |
| `decode_fields(&[u8]) -> Result<Self>` | 解析**裸字段区**（无结构头包裹） |
| `read_from_current(&mut TarsDecoder)` | 从解码器当前位置读字段 |

> **`decode` vs `decode_fields` 别用错**：Dart 虎牙的实际用法是
> `HYMessage.readFrom(TarsInputStream(wSPushMessage.msg))` —— 直接对 payload 读字段，
> **外层没有 `STRUCT_BEGIN`**。这种情况下必须用 `decode_fields`，用 `decode` 会报
> 「字段类型不符: tag=0 期望 结构体，实为 BYTE」。

### 4.2 解码器（`TarsDecoder`）

字段读取 —— 严格版返回 `Err`，`_or` 版给默认值（对齐 Dart `isRequire=false`）：

| 方法 | 缺失/类型不符时 |
|------|----------------|
| `read_i64(tag)` / `read_i64_or(tag, default)` | `Err` / `default` |
| `read_f64(tag)` / `read_f64_or(tag, default)` | 同 |
| `read_bool(tag)` / `read_bool_or(tag, default)` | 同 |
| `read_string(tag)` / `read_string_or(tag, &str)` | 同 |
| `read_bytes(tag)` / `read_bytes_or(tag)` | 同 |
| `read_value(tag)` | 动态值（`TarsValue`），无需预知字段类型 |

容器与结构体：

| 方法 | 说明 |
|------|------|
| `read_list(tag, \|d\| ...)` | 元素类型由回调给出（线上元素 tag 恒 0，回调内一般用 `read_i64(0)`） |
| `read_map(tag, \|d\| k, \|d\| v)` | key tag=0 / value tag=1 |
| `read_str_bytes_map(tag)` | `Map<String, Vec<u8>>`（TUP `tRsp` 容器形态） |
| `read_str_str_map(tag)` | `Map<String, String>`（`RequestPacket.status` 形态） |
| `read_struct(tag, \|d\| ...)` | 定位 `STRUCT_BEGIN` → 回调 → 自动跳到 `STRUCT_END` |

字节层工具：`read_field_head` / `skip_to_tag` / `skip_field` / `skip_to_struct_end` /
`read_raw_u8` / `read_raw_i32` / `read_raw_bytes(n)` / `position` / `remaining` / `at(buf, pos)`。

### 4.3 编码器（`TarsEncoder`）

| 方法 | 说明 |
|------|------|
| `write_i64(v, tag)` | 按值域自动选宽；`v == 0` 只写 `ZERO_TAG` 头 |
| `write_bool(v, tag)` | 同 `write_i64(v as i64, tag)` |
| `write_f32(v, tag)` / `write_f64(v, tag)` | `FLOAT` / `DOUBLE` |
| `write_string(s, tag)` | 空串 / `<=255` 字节走 `STRING1`，否则 `STRING4` |
| `write_bytes(&[u8], tag)` | `SIMPLE_LIST` |
| `write_list(&[TarsValue], tag)` | `LIST` |
| `write_map(&[(TarsValue, TarsValue)], tag)` | `MAP` |
| `write_str_map(&BTreeMap<String, Vec<u8>>, tag)` | `MAP<String, bytes>`，键序确定 |
| `write_struct(&[(i32, TarsValue)], tag)` | `STRUCT_BEGIN` + 字段 + `STRUCT_END` |
| `write_value(&TarsValue, tag)` | 按值形态分派 |
| `write_nested_struct(tag, \|e\| ...)` | **嵌套结构体字段**（`STRUCT_BEGIN` + 回调 + `STRUCT_END`） |
| `write_struct_begin()` / `write_struct_end()` | 单独写首尾标记 |
| `into_bytes()` / `as_slice()` / `len()` | 取结果 |

> **嵌套结构体不要用 `write_bytes(&sub.encode()?, tag)`** —— 那会写成 `SIMPLE_LIST`，
> 与读侧 `read_struct` 期待的 `STRUCT_BEGIN` 不匹配。写侧用
> `write_nested_struct(tag, |e| sub.write_to(e))?`，读侧用
> `d.read_struct(tag, Sub::read_from)?`。

### 4.3.1 常见踩坑点

| # | 坑 | 说明 |
|---|-----|------|
| 1 | `write_bytes` 产出比预期多 2 字节 | `SIMPLE_LIST` 头 + 内层 `Byte` 头 + **长度自身的字段头** + 长度值 + 数据。`write_bytes(&[1,2,3], 2)` 共 7 字节 |
| 2 | `write_i64(0, tag)` 只产出 1 字节 | 零值走 `ZERO_TAG`，无载荷。手搓字节流时别多给值字节 |
| 3 | `BYTE` 按无符号读 | `read_i64` 遇 `BYTE` 返回 `0..=255`。不要往 `BYTE` 分支的 tag 塞负数 |
| 4 | `decode` vs `decode_fields` | 见 §4.1 说明 |
| 5 | `UniPacket` 包体是**平铺**字段 | 无 `STRUCT_BEGIN` 包裹；与 `TarsMessage` 的包裹形态不同，两者不可混用 |
| 6 | `bool` 无线上类型 | `write_bool` 编为 `BYTE`，`read_value` 读回是 `Int(1)` 而非 `Bool(true)` |

### 4.4 动态值（`TarsValue`）

```rust
pub enum TarsValue {
    Int(i64), Double(f64), Bool(bool), Str(String),
    Bytes(Vec<u8>), List(Vec<TarsValue>),
    Map(Vec<(TarsValue, TarsValue)>), Struct(Vec<(i32, TarsValue)>),
}
```

构造：`TarsValue::int(7)` / `string("a")` / `str("a")` / `bytes(vec![1])` / `double(1.5)` /
`boolean(true)` / `list(..)` / `map(..)` / `strukt(..)`，以及 `From<i32>/<i64>/<bool>/<f64>/<&str>/<String>/<Vec<u8>>`。
访问：`as_int` / `as_str` / `as_bytes` / `as_list` / `as_map` / `as_struct` / `as_double` / `as_bool`（类型不符返回 `None`）。

### 4.5 裸缓冲（`WriteBuffer` / `ReadBuffer`）

```rust
let mut w = slive_core::tars::WriteBuffer::new();
w.set_endian(Endian::Little);          // 运行时切换
w.put_i32(-2); w.put_f64(1.5);
w.put_string_u8_len("弹幕");            // 1 字节长度前缀
w.put_string_u32_len("ab");             // 4 字节长度前缀
let bytes = w.into_bytes();

let mut r = slive_core::tars::ReadBuffer::new(&bytes);
r.set_endian(Endian::Little);
assert_eq!(r.read_i32().unwrap(), -2);
```

整型：`put_i8/i16/i32/i64`、`put_u8/u16/u32/u64`、`put_bool`；
浮点：`put_f32/f64`；其他：`put_bytes`、`put_repeated`、`align_to`、
`put_string_u8_len`、`put_string_u32_len`。
读侧对称：`read_i8/i16/i32/i64`、`read_u8/u16/u32/u64`、`read_bool`、`read_f32/f64`、
`read_bytes(n)`、`read_to_end`、`read_string_u8_len`、`read_string_u32_len`、
`read_u32_array(n)`、`read_i64_array(n)`、`seek`、`skip`、`remaining`、`remaining_slice`。

### 4.6 TUP 封包

```rust
use slive_core::tars::{TarsEncoder, TarsStruct, UniPacket};

let mut p = UniPacket::new();                 // i_version = TUP3(3), c_packet_type = 0
p.set_servant_name("Obj");
p.set_func_name("getCdnToken");
p.set_request_id(1);
p.put("tReq", req.encode()?).unwrap();        // 参数区
let body = p.encode()?;                       // 4 字节大端总长 + body

let rsp = UniPacket::decode(&resp_bytes)?;    // 解响应
let code = rsp.result_code();                 // 参数区 "" 键的返回码
let t_rsp = rsp.resp_bytes();                 // "tRsp" 结构体字节
```

| 类型 | 方法 |
|------|------|
| `UniPacket` | `new` / `set_version` / `version` / `set_servant_name` / `set_func_name` / `set_request_id` / `put` / `encode` / `decode` / `result_code` / `result_code_from_status` / `req_bytes` / `resp_bytes` |
| `UniAttribute` | `new_tup3` / `with_version` / `version` / `set_version` / `put_bytes` / `put_typed`（TUP2） / `get_bytes` / `get_typed_bytes` / `get_value` / `get_or` / `encode` / `decode` / `decode_tup2` / `decode_tup3` / `len` / `is_empty` |
| `RequestPacket` | `new_tup3` / `encode` / `decode` / `to_fields` / `result_code` / `result_desc` |
| `TarsMessage` | `encode` / `decode` / `get(key)`（`RequestPacket` 头 + `Map<String,bytes>` 体） |

常量：`PACKET_TYPE_TARSNORMAL=0`、`PACKET_TYPE_TARSONEWAY=1`、`PACKET_TYPE_TUP=2`、
`PACKET_TYPE_TUP3=3`、`UNI_PACKET_HEAD_SIZE=4`、`MAX_TAG=255`、`TARS_MAX_STRING_LENGTH=100MiB`；
`consts::STATUS_RESULT_CODE` / `STATUS_RESULT_DESC` / `TUP_RESULT_KEY` 等。

## 5. 与 Dart `tars_dart` 的对应关系与**已知差异**

### 5.1 行为等价（刻意保持）

| 项 | 说明 |
|----|------|
| `BYTE` 按**无符号**读 | Dart `readInt(1)` 走 `getUint8`，与官方 C++ `unsigned char` 一致。写入 `-5` 读回 `251`。**未擅自"修正"为有符号** |
| 零值只写头 | `ZERO_TAG` 不带载荷字节 |
| 长度按 UTF-8 字节数 | 非 char 数 |
| 长度字段自带字段头 | 长度本身是 tag=0 的整型字段，有完整头字节 |
| `readBytes` 兼容 `LIST` 形态 | Dart `readBytes` 同时接受 `SIMPLE_LIST` 与 `LIST` of int |
| TUP2 先试后 TUP3 | `UniAttribute::decode` 保留 Dart 的版本探测顺序 |
| `UniPacket` 包体平铺 | Dart `UniPacket.encode` 走 `package.writeTo`，逐字段写出、**无** `STRUCT_BEGIN` 包裹（与 `TarsMessage` 的 `STRUCT_BEGIN` 包裹不同） |
| `context`/`status` 值是字符串 | Dart `Map<String,String>` 键值都走 `writeString`；读侧 `read_str_str_map` 才对得上 |
| `bool` 无线上类型 | Dart `writeBool` -> `writeByte` -> `BYTE`；`read_value` 读回是 `Int` 而非 `Bool` |

### 5.2 有意为之的差异

| # | 差异 | 理由 |
|---|------|------|
| 1 | **不 panic**：越界/类型不符/非法 UTF-8 一律 `Err(SliveError::Decode)` | Dart 抛 `RangeError`/`FormatException`。弹幕链路要求畸形包不炸进程 |
| 2 | **不再吞异常**：Dart `skipToTag` 用 try/catch 吞掉并返回 `false` | 改为返回 `Err`；需要「缺失即默认值」时显式用 `*_or` 系列，语义更明确、不会静默掩盖数据问题 |
| 3 | **非法 UTF-8 不做 lossy 替换** | Dart `utf8.decode` 抛异常。弹幕昵称/内容被静默改写会产生错数据，直接报错由上层丢弃该条更安全 |
| 4 | `BYTE`/`SHORT`/`INT`/`LONG` 宽度由编码侧按值域选 | 与 Dart 一致（`writeInt` 逻辑照搬）。**注意负数会被写进 `BYTE` 分支**，读取时按无符号还原 —— 与 Dart 行为相同，平台侧不要往 `BYTE` 字段塞负数 |
| 5 | 缺 `UnimplementedError` 类空壳 | Dart `UniPacket.encode()` 在 TUP2 下抛 `UnimplementedError`；本模块返回 `Err(InvalidInput)`，符合「无 TODO 空壳」要求 |
| 6 | Map 用 `BTreeMap` 而非 `LinkedHashMap` | 键序确定，便于对拍。虎牙/斗鱼协议均不依赖 Map 键序 |
| 7 | 无 `deepCopy` / `displayAsString` | Dart 里这两个在 `UniAttribute` 是 `throw UnimplementedError`，本模块不提供 |
| 8 | `BasicClassTypeUtil` 的类型名字符串未实现 | 仅 TUP2 `put_typed` 需要；虎牙走 TUP3，实际用不到。`put_typed(name, type_name, bytes)` 由调用方直接给类型名 |
| 9 | 字符串 > `TARS_MAX_STRING_LENGTH`(100MiB) 报错 | Dart 仅在 `STRING4` 读取时校验；本模块写入侧也拦一道，防内存放大 |
| 10 | 裸缓冲默认大端（Dart 为 `Endian.host`） | 消除「跑在大小端机器上字节序不同」的隐患；TARS 字段本就恒大端，行为等价 |

### 5.3 与 DTV 的差异

`C:\DTV\src-tauri\src\platforms\huya/` 用第三方 `tars-stream`（nightly）。
本模块为手写，**不参考其 API 形态**，仅协议形态参考；`Cargo.toml` 未引入任何新依赖。

## 6. 测试

| 位置 | 用例数 | 覆盖 |
|------|--------|------|
| 各源文件 `#[cfg(test)]`（含 `packet_tests.rs` / `buffer/reader_tests.rs`） | 58 | 单元级边界与错误分支 |
| `tests/ac_tars_codec.rs` | 30 | 字节序切换、整型选宽、字符串 STRING1/4 切换、bytes 两形态、数组/Map/结构体往返、tag 边界、错误路径（不 panic）、超长/负长度拒绝 |
| `tests/ac_tars_wire.rs` | 10 | **手工字节流 -> 解码对拍**（含构造逻辑注释） |
| **合计** | **98** | 全部通过 |

对拍用例（`ac_tars_wire.rs`）按 Dart 语义**逐字节手工构造**并在注释中给出推导：

| 常量 | 内容 |
|------|------|
| `HYPUSH_MANUAL` | 复刻虎牙 `HYPushMessage`：`pushType=7(tag0)` / `uri=1400(tag1)` / `msg=[AA,BB](tag2)` / `protocolType=0(tag3)` |
| `OUTER_MANUAL` | 嵌套结构体（`STRUCT_BEGIN`/`STRUCT_END` 与 tag 定位） |
| `WIDE_MANUAL` | `tag >= 15` 的两字节字段头 |
| `MAP_MANUAL` / `LIST_MANUAL` | Map / List 头部布局 |
| STRING4 / STRING1 UTF-8 | 长度切换与 UTF-8 字节长度 |

其中 `encoder_reproduces_the_manual_byte_stream_exactly` 做**双向对拍**：
本模块编码结果必须与手工字节流逐字节相同。

`order_helpers_match_std_byte_layout` 直接与标准库 `to_be_bytes()` / `to_le_bytes()` 对拍 ——
比「往返对称」更强：往返对称在**读写两侧共享同一个错误**时也会通过
（本模块开发中确实出现过这种 bug，靠这条用例抓出）。

### 运行

```bash
cd simple_live_app/rust
cargo test -p slive-core --test ac_tars_codec --test ac_tars_wire
```

### 自检结果

- `cargo build -p slive-core`：通过
- `cargo clippy -p slive-core --all-targets`：`src/tars/` **零告警**
- 单文件行数门禁：全部 <= 300 行
- 测试：**98 passed / 0 failed**

完整日志：`docs/rust-core/evidence-tars-build-test.log`。

> 注：全量 `cargo test -p slive-core` 会一并编译 `platforms/douyin`、`platforms/douyin` 等
> 并行任务的在制品，其编译错误与本模块无关。故本模块的 98 条用例另在**隔离 crate**
> （仅含 `slive-core/src/error.rs` + `src/tars/`，无任何其他平台代码）复核通过，
> 过程与结果见证据日志 §2。

## 7. 平台侧接入指引

### 虎牙（IP-4）

1. 消息定义放 `platforms/huya/danmaku/tars_msgs.rs`，逐个实现 `TarsStruct`；
2. WSS 注册包用 `TarsEncoder` 手工拼装（`WebSocketCommand` 是**自定义二进制格式，非 TARS**，
   注意与 `HYPushMessage` 的 TARS 段区分）；
3. 弹幕解码：`TarsDecoder::new(frame)` → 先读首字节判消息类型（7 / 22）→ `TarsDecoder::at(buf, 1)`
   → 对应结构体 `decode`；
4. TUP over HTTP（`getCdnToken` 等）：`UniPacket` 构造 → POST → `UniPacket::decode` →
   `result_code()` → `resp_bytes()` → 结构体 `decode`。

### 斗鱼（IP-3）

> **核实结论：斗鱼弹幕不使用 TARS。**
> Dart `platforms/douyu/douyu_danmaku.dart` 用的是 STT（`key@=value/` 纯文本 + `/` 分隔 +
> `//` 嵌套数组），分帧为 `simple_live_core/lib/src/common/binary_writer.dart` 的
> **小端** `BinaryWriter/BinaryReader`。全仓 `tars_dart` 引用只出现在 `platforms/huya/*`。
> 故斗鱼侧**不需要** `crate::tars`；其分帧用 `WriteBuffer`/`ReadBuffer` + `Endian::Little` 即可，
> 或直接沿用 `ws/frame.rs` 的既有风格。
