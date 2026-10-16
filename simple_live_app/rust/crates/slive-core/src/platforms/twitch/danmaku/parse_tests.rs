//! `#[cfg(test)]` 测试体（从 `parse.rs` 拆出，避免单文件超 300 行硬门禁）。

    use super::*;

    #[test]
    fn parses_typical_privmsg_with_color() {
        let frame = "@badge-info=;badges=;color=#FF0000;display-name=Alice;id=abc;\
                     mod=0;room-id=12345;subscriber=0;tmi-sent-ts=1700000000000;user-id=42 \
                     :alice!alice@alice.tmi.twitch.tv PRIVMSG #xqc :hello world";
        let out = parse_frame(frame);
        assert_eq!(out.messages.len(), 1);
        let msg = &out.messages[0];
        assert_eq!(msg.message_type, LiveMessageType::Chat);
        assert_eq!(msg.message, "hello world");
        assert_eq!(msg.user_name, "Alice");
        assert_eq!(msg.user_id.as_deref(), Some("42"));
        assert_eq!(msg.color, LiveMessageColor::new(255, 0, 0));
        assert!(out.replies.is_empty());
    }

    #[test]
    fn message_without_color_tag_is_dropped_per_dart() {
        // Q-A（钉死）：Dart 三正则缺 color 即整条丢弃；Rust **照搬**（修正会违反 AC-30）。
        let frame = "@display-name=Bob;room-id=1;user-id=7 \
                     :bob!bob@bob.tmi.twitch.tv PRIVMSG #xqc :hi";
        assert!(parse_frame(frame).messages.is_empty(), "无 color -> 丢弃");
    }

    #[test]
    fn message_without_display_name_is_dropped_per_dart() {
        // Q-A：三正则缺 display-name 即丢弃（**不做 nick 回退**）。
        let frame = "@color=#FF0000;room-id=1;user-id=9 \
                     :carol!carol@carol.tmi.twitch.tv PRIVMSG #xqc :yo";
        assert!(parse_frame(frame).messages.is_empty(), "无 display-name -> 丢弃");
    }

    #[test]
    fn malformed_color_tag_is_dropped_per_dart() {
        // Dart 正则 `color=#([a-zA-Z0-9]{6});` 要求恰好 6 位；位数不足/超长均不命中。
        for color in ["#FFF", "#FFFFFFF", "#GGGGGG"] {
            let frame = format!("@color={color};display-name=A :a!a@a PRIVMSG #xqc :x");
            assert!(
                parse_frame(&frame).messages.is_empty(),
                "color={color} 应不命中 6 位正则"
            );
        }
    }

    #[test]
    fn ping_replies_with_whole_frame_pong_per_dart() {
        // Q-B（钉死）：`replaceFirst` 作用于**整帧**，尾随字符一并保留。
        let out = parse_frame("PING :tmi.twitch.tv\n");
        assert_eq!(out.replies, vec!["PONG :tmi.twitch.tv\n".to_string()]);
        assert!(out.messages.is_empty());
    }

    #[test]
    fn ping_reply_carries_following_lines_per_dart() {
        // Q8（钉死）：混帧时回包带上后续 PRIVMSG 行 —— 这是 Dart 现状，**照搬**。
        let frame = "PING :tmi.twitch.tv\n@color=#FF0000;display-name=A;user-id=1 \
                     :a!a@a PRIVMSG #xqc :hi\n";
        let out = parse_frame(frame);
        assert_eq!(out.replies.len(), 1);
        assert!(
            out.replies[0].contains("PRIVMSG"),
            "Q8：回包应含后续 PRIVMSG 行，实际 {}",
            out.replies[0]
        );
        assert_eq!(out.messages.len(), 1, "PRIVMSG 行仍应被解析");
    }

    #[test]
    fn multi_line_frame_yields_all_messages_in_order() {
        // 逐行产出，顺序与帧内一致（`18-fixtures-multiplatform.md §3.3`）。
        // 三正则齐全才有 color 标签，故每行都须带 `color=`。
        let frame = concat!(
            "@color=#FF0000;display-name=A;user-id=1 :a!a@a PRIVMSG #xqc :first\r\n",
            "@color=#00FF00;display-name=B;user-id=2 :b!b@b PRIVMSG #xqc :second\r\n"
        );
        let out = parse_frame(frame);
        assert_eq!(out.messages.len(), 2);
        assert_eq!(out.messages[0].message, "first");
        assert_eq!(out.messages[1].message, "second");
        assert_eq!(out.messages[0].color, LiveMessageColor::new(255, 0, 0));
        assert_eq!(out.messages[1].color, LiveMessageColor::new(0, 255, 0));
    }

    #[test]
    fn non_chat_commands_are_ignored() {
        for line in [
            ":tmi.twitch.tv 001 justinfan1 :Welcome, GLHF!",
            ":justinfan1!justinfan1@justinfan1.tmi.twitch.tv JOIN #xqc",
            ":xqc!xqc@xqc.tmi.twitch.tv ROOMSTATE #xqc",
            "@color=;display-name=A;mod=0 :a!a@a USERSTATE #xqc",
            "PONG tmi.twitch.tv :ok",
            "@msg-id=host_on :tmi.twitch.tv NOTICE #xqc :This room is in host mode.",
        ] {
            let out = parse_frame(line);
            assert!(out.messages.is_empty(), "{line} 不应产出消息");
            assert!(out.replies.is_empty(), "{line} 不应产出待发帧");
        }
    }

    #[test]
    fn empty_trailing_is_not_emitted() {
        let out = parse_frame("@display-name=A :a!a@a PRIVMSG #xqc :");
        assert!(out.messages.is_empty());
    }

    #[test]
    fn colon_inside_message_is_preserved() {
        let frame = "@display-name=A;user-id=1 :a!a@a PRIVMSG #xqc :look: http://a/b?c=d";
        let out = parse_frame(frame);
        assert_eq!(out.messages[0].message, "look: http://a/b?c=d");
    }

    #[test]
    fn tag_escapes_are_decoded() {
        let tags = parse_tags(r"system-msg=foo\sbar\:baz\\qux;display-name=A");
        assert_eq!(tags.get("system-msg").unwrap(), "foo bar;baz\\qux");
        assert_eq!(tags.get("display-name").unwrap(), "A");
    }

    #[test]
    fn tags_without_value_map_to_empty_string() {
        let tags = parse_tags("mod;subscribed=0");
        assert_eq!(tags.get("mod").unwrap(), "");
        assert_eq!(tags.get("subscribed").unwrap(), "0");
    }

    #[test]
    fn nick_of_strips_ident_and_host() {
        assert_eq!(nick_of("alice!alice@alice.tmi.twitch.tv"), "alice");
        assert_eq!(nick_of("alice"), "alice");
        assert_eq!(nick_of(""), "");
    }

    #[test]
    fn six_digit_hex_color_is_exact() {
        // Twitch 实际总发 6 位十六进制（`color=#RRGGBB`）—— 精确还原。
        for (hex, want) in [
            ("#FF0000", LiveMessageColor::new(255, 0, 0)),
            ("#00FF00", LiveMessageColor::new(0, 255, 0)),
            ("#1E90FF", LiveMessageColor::new(30, 144, 255)),
            ("#FFFFFF", LiveMessageColor::white()),
        ] {
            let frame = format!("@color={hex};display-name=A :a!a@a PRIVMSG #xqc :x");
            let out = parse_frame(&frame);
            assert_eq!(out.messages[0].color, want, "hex={hex}");
        }
    }

    #[test]
    fn three_digit_hex_is_dropped_before_color_conversion() {
        // 3 位形式不命中 Dart 的 6 位正则 -> 在 Q-A 阶段即被丢弃，
        // 根本不会进入 `number_to_color`（故不涉及共享实现的补零 quirks）。
        let out = parse_frame("@color=#0F0;display-name=A :a!a@a PRIVMSG #xqc :x");
        assert!(out.messages.is_empty());
    }
