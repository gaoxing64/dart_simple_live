# 确定性 golden（AC-11 / AC-21 / AC-35）

> **本目录的期望值由已验证的 Dart 算法独立推导**，**不是**被测 Rust 代码的产出 → 满足 AC-35「实现者改不动、不自证」。

## `golden-join-packet.json`（AC-11）

- 推导自 `bilibili_danmaku.dart:119-145`（`encodeData`）与 `:88-102`（`joinRoom`）。
- 输入：`room_id=6, uid=0, token="test-token-abc", buvid="buvid3-FIXED"`。
- 断言：`ws::frame::encode_packet(json, 7)` 输出**逐字节**等于文件内 `join_packet.bytes`。
- **关键点**：头 16 字节 = `len(u32 BE) / hdrlen(u16=16) / protover(u16) / op(u32) / seq(u32)`；其中**头的 protover 恒为 0**（`encodeData` 写死 0），`protover=3` 只出现在 JSON body 内。join 包 `op=7`、心跳包 `op=2`。
- 心跳包 golden：`00 00 00 10 00 10 00 00 00 00 00 02 00 00 00 01`。

## `golden-wbi.json`（AC-21）

- 推导自 `bilibili_site.dart:418-483`（`mixinKeyEncTab`）/ `:505-508`（`getMixinKey`）/ `:510-534`（`getWbiSign`）。
- 输入：公开示例 `img_key=7cd084941338484aae1ad9425b84077c`、`sub_key=4932caff0ff746eab6f01bf08b70ac45`、`wts=1700000000`、`params={room_id:6}`。
- 期望：`mixin_key=ea1db124af3c7062474693fa704f4ff8`、`w_rid=46e0afca2af785f6dbdc24935d856d79`。
- 算法要点：`mixinKey = 前32位( origin[i] for i in mixinKeyEncTab )`，`origin = img_key+sub_key`；`w_rid = md5( sorted_kv_join("&") + mixinKey )`，值先过滤 `!'()*`。

> ⚠️ 断言 `w_rid` 时，`wts` 必须是**注入的固定值**（不可取当前时间），否则 golden 失效。实现须把时间源抽象为可注入（用于测试固定 `wts`）。

## 反作弊要求

- **禁止**：先跑实现 → 把输出写回 `golden-*.json`。这等于「改基线掩盖缺陷」（`test-integrity-anti-gaming.md §3`）。
- **允许**：期望值变更仅当**算法契约变化**，且须在 PR 说明引用 `13-spec.md` 对应条目 + 经 QA 复核。
