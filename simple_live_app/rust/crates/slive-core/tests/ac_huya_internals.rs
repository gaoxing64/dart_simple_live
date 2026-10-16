//! IP-4 虎牙内部构造与解码的集成测试（覆盖私有实现路径）。
//!
//! 与 [`ac_huya_http`] / [`ac_huya_danmaku`] 的分工：那两个文件按**公开 API** 断言
//! 夹具；本文件补**内部构造器与解码分支**（TUP 响应构造器、帧组装、脏帧不 panic）。
//! 用例从各源文件的 `#[cfg(test)]` 块迁出（迁出以守住单文件 ≤300 行门禁）。

#![allow(clippy::too_many_arguments)]

use slive_core::platforms::huya::danmaku::frames::{self, HuyaFrame};
use slive_core::platforms::huya::danmaku::{args, tars_cdn, tars_msgs, tars_ws_v2};


use slive_core::platforms::huya::anti_code::{
    build_anti_code, build_play_url, parse_anti_code, parse_query, DEFAULT_CTYPE,
};
use slive_core::platforms::huya::utils::{md5_hex, rotl64};
use slive_core::platforms::huya::tup::{self, 
    attributes_summary, build_tup_response,
    FUNC_CDN_TOKEN_EX, FUNC_HEADLINE_BOARD, SERVANT_LIVE_UI, SERVANT_WUP_UI,
};
use slive_core::tars::{TarsDecoder, TarsEncoder, TarsStruct, UniPacket};


    /// 构造与线上一致的帧：`tag0=cmdType` + `tag1=data` + tag2..6（Dart 的 7 字段集）。
    /// 构造与线上一致的帧：`data` 载荷是**裸字段表**（服务端形态，无外层 STRUCT_BEGIN）。
    fn push_frame(cmd_type: i32, uri: i64, msg: Vec<u8>) -> Vec<u8> {
        use slive_core::tars::TarsStruct;
        let mut encoder = slive_core::tars::TarsEncoder::new();
        tars_msgs::HyPushMessage {
            push_type: 0,
            uri,
            msg,
            protocol_type: 0,
        }
        .write_to(&mut encoder)
        .expect("写裸字段表");
        let body = encoder.into_bytes();
        frames::build_command(cmd_type, &body).expect("组帧")
    }

    #[test]
    fn join_frame_uses_cmd16_and_carries_group_ids() {
        let frame = frames::build_join_frame(&["live:123".to_string(), "chat:123".to_string()])
            .expect("构造 join 帧");
        let mut dec = TarsDecoder::new(&frame);
        assert_eq!(dec.read_i64_or(0, -1), frames::cmd::REGISTER_GROUP_REQ as i64, "cmdType");
        // 载荷里应能看到两个 groupId
        let body = String::from_utf8_lossy(dec.remaining_slice());
        assert!(body.contains("live:123"), "实际 {body}");
        assert!(body.contains("chat:123"), "实际 {body}");
    }

    #[test]
    fn heartbeat_frame_uses_cmd20_with_empty_payload() {
        let frame = frames::build_heartbeat_frame().expect("构造心跳帧");
        let mut dec = TarsDecoder::new(&frame);
        assert_eq!(dec.read_i64_or(0, -1), frames::cmd::HEART_BEAT_REQ as i64, "cmdType");
        assert!(dec.read_bytes_or(1).is_empty(), "心跳载荷为空");
    }

    #[test]
    fn decode_chat_message() {
        let message = tars_msgs::HyMessage {
            user_info: tars_msgs::HySender {
                s_nick_name: "观众乙".to_string(),
                ..Default::default()
            },
            content: "来了来了".to_string(),
            bullet_format: tars_msgs::HyBulletFormat {
                font_color: 16777215,
                ..Default::default()
            },
        };
        // msg 内层是裸字段表（服务端形态），不能用 encode()（多一层 STRUCT_BEGIN）
        use slive_core::tars::TarsStruct;
        let mut encoder = slive_core::tars::TarsEncoder::new();
        message.write_to(&mut encoder).expect("写裸字段表");
        let frame = push_frame(frames::cmd::MSG_PUSH_REQ, frames::URI_CHAT, encoder.into_bytes());
        match frames::decode_frame(&frame) {
            HuyaFrame::Chat {
                user_name,
                content,
                font_color,
            } => {
                assert_eq!(user_name, "观众乙");
                assert_eq!(content, "来了来了");
                assert_eq!(font_color, 16777215);
            }
            other => panic!("期望 Chat，实际 {other:?}"),
        }
    }

    #[test]
    fn decode_online_from_raw_int() {
        let mut payload = TarsEncoder::new();
        payload.write_i64(4321, 0).expect("写人气");
        let frame = push_frame(frames::cmd::MSG_PUSH_REQ, frames::URI_ONLINE, payload.into_bytes());
        assert_eq!(frames::decode_frame(&frame), HuyaFrame::Online { online: 4321 });
    }

    #[test]
    fn unknown_uri_is_ignored() {
        let frame = push_frame(frames::cmd::MSG_PUSH_REQ, 999_999, vec![1, 2, 3]);
        assert_eq!(frames::decode_frame(&frame), HuyaFrame::Ignored);
    }

    #[test]
    fn malformed_frame_does_not_panic() {
        assert!(matches!(
            frames::decode_frame(&[]),
            HuyaFrame::Malformed(_)
        ));
        assert!(matches!(frames::decode_frame(&[0xFF]), HuyaFrame::Malformed(_)));
    }

    #[test]
    fn online_with_non_tars_payload_is_malformed() {
        let frame = push_frame(frames::cmd::MSG_PUSH_REQ, frames::URI_ONLINE, vec![1, 2]);
        assert!(matches!(frames::decode_frame(&frame), HuyaFrame::Malformed(_)));
    }

    #[test]
    fn ws_msg_item_roundtrips() {
        let item = tars_ws_v2::WsMsgItem {
            i_uri: frames::URI_SUPER_CHAT,
            s_msg: vec![9, 8, 7],
            l_msg_id: 42,
        };
        let bytes = item.encode().expect("编码");
        assert_eq!(tars_ws_v2::WsMsgItem::decode(&bytes).expect("解码"), item);
    }

    #[test]
    fn v2_frame_with_sc_uri_reports_event() {
        let item = tars_ws_v2::WsMsgItem {
            i_uri: frames::URI_SUPER_CHAT,
            s_msg: vec![],
            l_msg_id: 1,
        };
        let push = tars_ws_v2::WsPushMessageV2 {
            s_group_id: "live:1".to_string(),
            v_msg_item: vec![item],
        };
        // V2 帧的 data 载荷就是 WsPushMessageV2 的裸字段表（不经 HyPushMessage 包裹）
        use slive_core::tars::TarsStruct;
        let mut encoder = slive_core::tars::TarsEncoder::new();
        push.write_to(&mut encoder).expect("写裸字段表");
        let frame = frames::build_command(frames::cmd::MSG_PUSH_REQ_V2, &encoder.into_bytes())
            .expect("组帧");
        assert_eq!(frames::decode_frame(&frame), HuyaFrame::SuperChatEvent);
    }

    #[test]
    fn anon_user_id_matches_dart_shape() {
        let user = tup::anon_user_id("adr&13.1.0&official");
        assert_eq!(user.l_uid, 0);
        assert_eq!(user.s_guid, args::DEFAULT_GUID);
        assert!(user.s_token.is_empty());
        assert_eq!(user.s_huya_ua, "adr&13.1.0&official");
        assert!(user.s_cookie.contains("udb_appid=5002"));
        assert_eq!(user.s_device_info, args::DEFAULT_DEVICE);
    }

    #[test]
    fn tup_response_roundtrips_through_uni_packet() {
        let resp = tars_cdn::GetCdnTokenExResp {
            s_flv_token: "token-xyz".to_string(),
            i_expire_time: 120,
        };
        let bytes = build_tup_response(SERVANT_LIVE_UI, FUNC_CDN_TOKEN_EX, 0, Some(&resp))
            .expect("构造响应");
        let packet = UniPacket::decode(&bytes).expect("解码");
        assert_eq!(packet.result_code(), 0);
        let got = tars_cdn::GetCdnTokenExResp::decode(packet.resp_bytes().expect("tRsp")).expect("解 tRsp");
        assert_eq!(got, resp);
    }

    #[test]
    fn tup_response_carries_nonzero_code() {
        // 用 400（正值错误码）：共享 `write_i64` 的 BYTE 分支按无符号读，
        // 合成负值会回读成 251（`-1 & 0xFF`），故此处用正值验证「原样带出」语义。
        let bytes = build_tup_response::<tars_cdn::GetCdnTokenExResp>(SERVANT_LIVE_UI, FUNC_CDN_TOKEN_EX, 400, None)
            .expect("构造响应");
        let packet = UniPacket::decode(&bytes).expect("解码");
        assert_eq!(packet.result_code(), 400, "code 原样带出供 Api 错误使用");
    }

    #[test]
    fn reply_bytes_roundtrip_binary_payload() {
        let raw: Vec<u8> = (0u8..=255).collect();
        let reply = slive_core::http::HttpReply {
            status: 200,
            text: raw.iter().map(|b| *b as char).collect(),
            set_cookie: Vec::new(),
        };
        assert_eq!(tup::reply_bytes(&reply), raw, "二进制 body 必须无损还原");
    }

    #[test]
    fn attributes_summary_lists_keys() {
        let resp = tars_cdn::GetCdnTokenExResp::default();
        let bytes =
            build_tup_response(SERVANT_WUP_UI, FUNC_HEADLINE_BOARD, 0, Some(&resp)).expect("构造");
        let packet = UniPacket::decode(&bytes).expect("解码");
        let summary = attributes_summary(&packet);
        assert!(summary.contains_key(""), "返回码键");
        assert!(summary.contains_key("tRsp"), "响应键");
    }

// ---------------------------------------------------------------------------
// 反 anticode（自 src/platforms/huya/anti_code.rs 的 #[cfg(test)] 迁出，
// 迁出以守住「单文件 ≤300 行」门禁；覆盖不减少）
// ---------------------------------------------------------------------------


    /// 构造一份形态完整的 anticode（`fm` 为 base64("PREFIX_xxx")）。
    fn sample_anti_code() -> String {
        // base64("huyaFIXME_huyaFIXME") = "aHV5YUZJWE1FX2h1eWFGSU1F"
        "ctype=huya_pc_exe&t=102&fm=aHV5YUZJWE1FX2h1eWFGSU1F&fs=800&wsTime=66a1b2c3".to_string()
    }

    #[test]
    fn parse_extracts_all_fields() {
        let parts = parse_anti_code(&sample_anti_code())
            .expect("解析")
            .expect("有 fm");
        assert_eq!(parts.ctype, "huya_pc_exe");
        assert_eq!(parts.platform_id, 102);
        assert_eq!(parts.fs, "800");
        assert_eq!(parts.ws_time, "66a1b2c3");
    }

    #[test]
    fn missing_fm_passes_through_verbatim() {
        // Dart `huya_site.dart:351-353`：无 fm 时**原样返回** antiCode
        let anti = "ctype=huya_pc_exe&t=102&wsTime=66a1b2c3";
        assert!(parse_anti_code(anti).expect("解析").is_none());
        assert_eq!(
            build_anti_code(anti, "stream", 1, 1000).expect("构造").as_deref(),
            Some(anti),
            "无 fm 必须原样透传，而不是 None / 空串"
        );
    }

    #[test]
    fn missing_ws_time_is_error() {
        let anti = "fm=aHV5YUZJWE1FX2h1eWFGSU1F&fs=800";
        assert!(parse_anti_code(anti).is_err(), "缺 wsTime 必须报错");
    }

    #[test]
    fn default_ctype_applies_when_absent() {
        let anti = "fm=aHV5YUZJWE1FX2h1eWFGSU1F&fs=800&wsTime=66a1b2c3&t=102";
        let parts = parse_anti_code(anti).expect("解析").expect("有 fm");
        assert_eq!(parts.ctype, DEFAULT_CTYPE);
    }

    #[test]
    fn pc_path_emits_u_and_rotated_uid() {
        let result = build_anti_code(&sample_anti_code(), "abc-stream", 0x1122_3344, 1_700_000_000_000)
            .expect("构造")
            .expect("有签名");
        let pairs = parse_query(&result);
        let get = |k: &str| pairs.iter().find(|(pk, _)| pk == k).map(|(_, v)| v.clone());

        assert_eq!(get("ver").as_deref(), Some("1"));
        assert_eq!(get("fs").as_deref(), Some("800"));
        assert_eq!(get("t").as_deref(), Some("102"));
        assert_eq!(get("ctype").as_deref(), Some("huya_pc_exe"));
        // seqid = presenterUid + nowMs = 0x11223344 + 1_700_000_000_000
        assert_eq!(get("seqid").as_deref(), Some("1700287454020"));
        // PC 路径带 u（rotl64 后的 presenterUid），不带 uid/uuid
        // rotl64(0x11223344) = ((low<<8)|(low>>24)) & 0xFFFFFFFF = 0x22334411 = 573785105
        assert_eq!(get("u").as_deref(), Some("573785105"));
        assert!(get("uid").is_none(), "PC 路径不带 uid");
        assert!(get("uuid").is_none(), "PC 路径不带 uuid");
        // 8 个键：wsSecret/wsTime/seqid/ctype/ver/fs/fm/t/u
        assert_eq!(pairs.len(), 9, "实际 {} 个键: {result}", pairs.len());
    }

    #[test]
    fn ws_secret_matches_md5_formula() {
        let anti = sample_anti_code();
        let now = 1_700_000_000_000i64;
        let presenter = 0x1122_3344i64;
        let result = build_anti_code(&anti, "abc-stream", presenter, now as u64)
            .expect("构造")
            .expect("有签名");
        let ws_secret = parse_query(&result)
            .into_iter()
            .find(|(k, _)| k == "wsSecret")
            .map(|(_, v)| v)
            .expect("wsSecret");

        let seq_id = presenter as u64 + now as u64;
        let secret_hash = md5_hex(&format!("{seq_id}|huya_pc_exe|102"));
        let calc_uid = rotl64(presenter);
        let expected = md5_hex(&format!(
            "huyaFIXME_{calc_uid}_abc-stream_{secret_hash}_66a1b2c3"
        ));
        assert_eq!(ws_secret, expected, "wsSecret 必须等于公式值");
    }

    #[test]
    fn wap_path_uses_raw_uid_and_extra_fields() {
        let anti = "ctype=huya_pc_exe&t=103&fm=aHV5YUZJWE1FX2h1eWFGSU1F&fs=800&wsTime=66a1b2c3";
        let result = build_anti_code(anti, "abc-stream", 0x1122_3344, 1_700_000_000_000)
            .expect("构造")
            .expect("有签名");
        let pairs = parse_query(&result);
        let get = |k: &str| pairs.iter().find(|(pk, _)| pk == k).map(|(_, v)| v.clone());

        assert_eq!(get("uid").as_deref(), Some("287454020"), "WAP 用未旋转的 uid");
        assert!(get("uuid").is_some(), "WAP 路径带 uuid");
        assert!(get("u").is_none(), "WAP 路径不带 u");
    }

    #[test]
    fn play_url_flv_suffix_and_ratio() {
        let url = build_play_url("https://cdn.example/live", "stream1", false, "k=v", 2000)
            .expect("拼接");
        assert_eq!(url, "https://cdn.example/live/stream1.flv?k=v&codec=264&ratio=2000");
    }

    #[test]
    fn play_url_hls_suffix_without_ratio() {
        let url = build_play_url("https://cdn.example/live", "stream1", true, "k=v", 0)
            .expect("拼接");
        assert_eq!(url, "https://cdn.example/live/stream1.m3u8?k=v&codec=264");
    }
