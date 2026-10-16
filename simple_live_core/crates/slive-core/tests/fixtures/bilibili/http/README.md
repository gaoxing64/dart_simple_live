# HTTP 样本（F-01~F-10 / F-17~F-21）

## 文件

- `http-samples.json`：**15 个端点**的合成最小样本。每个 sample 含：
  - `endpoint` / `method` / `dart_source`（`bilibili_site.dart` 行号）
  - `target_ac`
  - `field_sources`：**每个字段 → Dart 解析代码行号**（可信度来源）
  - `response`（合成）/ `expected`（由 Dart 解析逻辑推导）
  - `variants`（空页 / 错误码 / 未开播 / 凭据无效等边界）
  - `verify_note`：合成假设 + 待核实点

## ⚠️ 合成声明（务必读）

- 样本**只含 Dart 解析代码真正读取的字段**，不含真实响应的完整结构（额外字段、更深的嵌套、类型差异）。
- 各 sample 均标 `synthetic: true`。
- **禁止把本文件当真实抓包**；落地前须用真实抓包替换（见 `15-test-plan.md §6 G-1`）。
- 字段可信度：字段名对应 Dart 行号 = B 级；真实响应嵌套/类型 = C 级（待核实）。

## 覆盖端点

| sample key | AC | 端点 |
|-----------|----|------|
| `room_v1_Area_getList` | AC-01 | `room/v1/Area/getList` |
| `xlive_web-interface_v1_second_getList` | AC-02 | `xlive/web-interface/v1/second/getList` |
| `xlive_web-interface_v1_second_getListByArea` | AC-03 | `xlive/web-interface/v1/second/getListByArea` |
| `www.bilibili.com_x_web-interface_search_type_live` | AC-04 | `x/web-interface/search/type?search_type=live` |
| `www.bilibili.com_x_web-interface_search_type_live_user` | AC-05 | `…?search_type=live_user` |
| `getInfoByRoom_plus_getDanmuInfo` | AC-06/22/23 | `xlive/web-room/v1/index/getInfoByRoom` + `getDanmuInfo` |
| `xlive_web-room_v2_index_getRoomPlayInfo` | AC-07/08/29 | `xlive/web-room/v2/index/getRoomPlayInfo` |
| `room_v1_Room_get_info` | AC-09 | `room/v1/Room/get_info` |
| `av_v1_SuperChat_getMessageList` | AC-10 | `av/v1/SuperChat/getMessageList` |
| `passport_qrcode_generate` | AC-18 | `passport-login/web/qrcode/generate` |
| `passport_qrcode_poll` | AC-19 | `passport-login/web/qrcode/poll` |
| `x_member_web_account` | AC-20/24 | `x/member/web/account` |
| `x_frontend_finger_spi` | AC-21 | `x/frontend/finger/spi` |
| `x_web-interface_nav` | AC-21 | `x/web-interface/nav` |
| `live.bilibili.com_lol` | AC-21 | `live.bilibili.com/lol`（HTML 文本） |

## 注入方式（架构 §8.4(c)）

`http::HttpClient` 抽象为 trait `HttpTransport`（默认 `ReqwestTransport`；测试 `MockTransport` 按 URL 匹配返回样本字节），并**记录请求次数/参数**（供 AC-25「不重试」与 NFR「请求数不增」断言）。与 Dart core 的 adapter 注入同构。

## 真实抓包替代路径（架构 §8.4(b)）

```bash
# 一次性、#[ignore]、仅在有网环境手动跑；产品路径不得依赖网络
cargo test -p slive-core -- --ignored record_http
```

> 录制产物须**脱敏**（不得含 cookie/credential，NFR 安全项）。
