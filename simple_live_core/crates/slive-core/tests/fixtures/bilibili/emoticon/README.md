# 表情包契约夹具（AC-16）

## 文件

- `emoticon-cases.json` —— **立即可用**。迁移自 `simple_live_core/test/bilibili_emoticon_test.dart` 的 **31 条契约**（含 `parseBilibiliEmoticons` group 30 条 + `LiveMessage` 序列化 1 条）。
  拆分子用例后共 **37 条断言组**（`EMO-18a/18b`、`EMO-22a/22b`、`EMO-24a/24b`、`EMO-28a..28e`）。

## 为什么是「已核实」（可信度 A 级）

- 输入 `info` 数组由 Dart 测试 helper `_infoOf`（`bilibili_emoticon_test.dart:22-45`）与 `_emot`（`:47-52`）**逐字复刻**。
- 断言 `expect` **只含 Dart 测试真正断言的内容**（不过度断言），避免「我们自己编的期望」。
- 运行时实现参考 `simple_live_core/lib/src/platforms/bilibili/bilibili_emoticon.dart:1-300`。

## 数据结构

```jsonc
{
  "_meta": { "expect_ops": { ... 见下 ... } },
  "cases": [
    {
      "id": "EMO-01",
      "origin_test": "从 extra.emots 解析出占位符与图片地址",
      "dart_source": "simple_live_core/test/bilibili_emoticon_test.dart:56",
      "input": { "info": [ ... ], "message": "哈哈哈[doge]笑死" },
      "expect": [ { "op": "not_null" }, { "op": "len_eq", "value": 1 }, ... ]
    }
  ]
}
```

## `expect` 断言操作符 → Rust 断言（`_meta.expect_ops`）

| op | Rust 断言 |
|----|-----------|
| `is_null` | `result.is_none()` |
| `not_null` | `result.is_some()` |
| `len_eq` | `result.as_ref().unwrap().len() == value` |
| `names_eq` | `result.iter().map(\|e\| e.name.clone()).collect::<Vec<_>>() == value` |
| `urls_eq` | `result.iter().map(\|e\| e.url.clone()).collect::<Vec<_>>() == value` |
| `first_name_eq` | `result[0].name == Some(value.into())` |
| `first_name_null` | `result[0].name.is_none()` |
| `first_url_eq` | `result[0].url == value` |
| `first_width_eq` | `result[0].width == Some(value)` |
| `first_height_eq` | `result[0].height == Some(value)` |
| `first_large_true` | `result[0].large == true` |
| `first_large_false` | `result[0].large == false` |
| `first_emoticon_unique_eq` | `result[0].emoticon_unique == Some(value.into())` |
| `no_url_ends_with` | `!result.iter().any(\|e\| e.url.ends_with(value))` |

## Rust 用例骨架（示意）

```rust
// crates/slive-core/tests/bilibili_emoticon.rs
#[derive(Deserialize)] struct Case { id: String, input: Input, expect: Vec<Assert> }
#[derive(Deserialize)] struct Input { info: Option<Vec<serde_json::Value>>, message: String }

#[test]
fn ac16_emoticons_contract() {
    let data: Fixture = load("fixtures/bilibili/emoticon/emoticon-cases.json");
    for c in data.cases {
        let got = parse_bilibili_emoticons(c.input.info.as_deref(), &c.input.message);
        apply_asserts(&c.id, &got, &c.expect);   // 逐 op 派发到上表断言
    }
}
```

> **注意**：`info` 元素含大量 `null`（Dart 稀疏数组），Rust 侧须用 `Option<Vec<Value>>` 并把 `Value::Null` 视作缺失，不可假设「元素非空」。
