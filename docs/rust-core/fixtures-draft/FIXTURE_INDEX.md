# 夹具索引（夹具 → AC → 来源 → 就绪度）

> 就绪度：[就绪] 可直接消费 ｜ [合成] 规格+最小样本待抓包 ｜ [待建] 依赖实现/环境

## 表情包（F-16 / AC-16）

| 夹具 | AC | 来源 | 就绪度 |
|------|----|------|--------|
| `emoticon/emoticon-cases.json` | AC-16 | `simple_live_core/test/bilibili_emoticon_test.dart`（31 契约 → 37 断言组） | [就绪] |

## 确定性 golden（AC-11 / AC-21 / AC-35）

| 夹具 | AC | 来源 | 就绪度 |
|------|----|------|--------|
| `golden/golden-join-packet.json` | AC-11 | 推导：`bilibili_danmaku.dart:88-102,119-145` | [就绪] |
| `golden/golden-wbi.json` | AC-21 | 推导：`bilibili_site.dart:418-534` | [就绪] |

## WS 帧（F-11~F-16 / AC-11~AC-16 / AC-28）

| 夹具 | AC | 来源 | 就绪度 |
|------|----|------|--------|
| `ws/frame-op3-online.bin` | AC-12 | 合成（帧格式 `bilibili_danmaku.dart:147-184`） | [就绪] |
| `ws/frame-op5-ver0-chat.bin` | AC-13, AC-14 | 合成 | [就绪] |
| `ws/frame-op5-ver2-zlib.bin` | AC-13 | 合成（zlib 标准格式） | [就绪] |
| `ws/frame-op5-ver0-superchat.bin` | AC-15 | 合成 | [就绪] |
| `ws/frame-op5-dirty-length.bin` | AC-28 | 合成（损坏帧） | [就绪] |
| `ws/frame-op5-ver3-brotli.bin` | AC-13 | 待生成（`brotli` crate 或抓包） | [待建] |

## HTTP 样本（F-01~F-10 / F-17~F-21 / AC-01~AC-10 / AC-18~AC-21 / AC-22~AC-29）

| sample key（`http/http-samples.json`） | AC | Dart 解析行号 | 就绪度 |
|----------------------------------------|----|---------------|--------|
| `room_v1_Area_getList` | AC-01, AC-27 | `bilibili_site.dart:51-80` | [合成] |
| `xlive_web-interface_v1_second_getList` | AC-02, AC-27 | `:82-114` | [合成] |
| `xlive_web-interface_v1_second_getListByArea` | AC-03, AC-27 | `:195-222` | [合成] |
| `www.bilibili.com_x_web-interface_search_type_live` | AC-04, AC-27 | `:273-304` | [合成] |
| `www.bilibili.com_x_web-interface_search_type_live_user` | AC-05, AC-27 | `:307-337` | [合成]（`is_live` 类型待核实） |
| `getInfoByRoom_plus_getDanmuInfo` | AC-06, AC-22, AC-23 | `:225-270` | [合成] |
| `xlive_web-room_v2_index_getRoomPlayInfo` | AC-07, AC-08, AC-29 | `:117-192` | [合成] |
| `room_v1_Room_get_info` | AC-09 | `:340-349` | [合成] |
| `av_v1_SuperChat_getMessageList` | AC-10, AC-27 | `:352-379` | [合成] |
| `passport_qrcode_generate` | AC-18 | `:561-573` | [合成] |
| `passport_qrcode_poll` | AC-19 | `:576-610` | [合成] |
| `x_member_web_account` | AC-20, AC-24 | `:613-635` | [合成] |
| `x_frontend_finger_spi` | AC-21 | `:389-414` | [合成] |
| `x_web-interface_nav` | AC-21 | `:484-503` | [合成] |
| `live.bilibili.com_lol` | AC-21 | `:536-550` | [合成] |

## 缺口（详见 `15-test-plan.md §6`）

- **真实抓包缺失（G-1）**：所有 HTTP 样本待真实抓包替换。
- **ver3 brotli 帧（G-2）**：待生成。
- **held-out 真实数据（§3.4）**：待抓包，当前仅有策略。
- **时钟注入（G-3）**：AC-26 WS 重连需实现侧提供可注入时间源。
