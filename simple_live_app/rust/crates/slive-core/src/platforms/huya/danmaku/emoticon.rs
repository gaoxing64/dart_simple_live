//! 虎牙弹幕表情包表（对齐 Dart `huya_emoticon.dart` 的 `_huyaEmoticons`，共 97 项）。
//!
//! 数据来源：服务端 `wupui/getExpressionEmoticonPackage`（`pkgId = 1`），
//! Dart 侧固化为常量表；本实现同样固化为常量（无调用方时不额外发请求 —— §9 性能约束）。
//!
//! 提取规则（对齐 Dart `_getHuyaEmoticonsFromContent`）：
//! 以 `\[[^\[\]]{1,16}\]` 语义扫描正文，命中表内的占位符转 [`LiveMessageEmoticon`]；
//! 未命中表（正文字面量）跳过；结果为空 -> `None`（不返回空数组）。

use crate::models::LiveMessageEmoticon;

/// 表情占位符 -> 图片地址（顺序与 Dart 一致，便于比对）。
pub const HUYA_EMOTICONS: &[(&str, &str)] = &[
    ("[666]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141729267685_pic.png"),
    ("[打呼]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141739514550_pic.png"),
    ("[滑稽]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141739087048_pic.png"),
    ("[难受]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141738689917_pic.png"),
    ("[亲亲]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141738398631_pic.png"),
    ("[无辜]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141738020039_pic.png"),
    ("[震惊]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141737604305_pic.png"),
    ("[大笑]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141715551855_pic.png"),
    ("[送花]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141715844572_pic.png"),
    ("[偷笑]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_15790913779295_pic.png"),
    ("[大哭]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141716134667_pic.png"),
    ("[嘿哈]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141728933000_pic.png"),
    ("[感动]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141729565605_pic.png"),
    ("[疑问]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141729809356_pic.png"),
    ("[喜欢]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141730048169_pic.png"),
    ("[奸笑]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141730570244_pic.png"),
    ("[赞]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16142231359365_pic.png"),
    ("[可爱]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141731673076_pic.png"),
    ("[傲慢]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141731879991_pic.png"),
    ("[开心]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141732333718_pic.png"),
    ("[拜拜]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141734545868_pic.png"),
    ("[害羞]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141734805267_pic.png"),
    ("[衰]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141735352150_pic.png"),
    ("[吐血]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141735632789_pic.png"),
    ("[嘴馋]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141736027641_pic.png"),
    ("[生气]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141736287609_pic.png"),
    ("[扶额]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141745475876_pic.png"),
    ("[闭嘴]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141745279636_pic.png"),
    ("[枯萎]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141744967831_pic.png"),
    ("[嘘]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141744784087_pic.png"),
    ("[笑哭]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141744424368_pic.png"),
    ("[流汗]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141744171474_pic.png"),
    ("[不看]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141743889665_pic.png"),
    ("[哈欠]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141743722981_pic.png"),
    ("[调皮]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141743387129_pic.png"),
    ("[鬼脸]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141743023277_pic.png"),
    ("[戳脸]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141742737113_pic.png"),
    ("[大哥]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141742503895_pic.png"),
    ("[困]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141741988394_pic.png"),
    ("[拥抱]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141741792413_pic.png"),
    ("[猪头]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141741241566_pic.png"),
    ("[骷髅]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141740823565_pic.png"),
    ("[臭臭]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141740598724_pic.png"),
    ("[心动]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141740425403_pic.png"),
    ("[狗头]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16164185817771_pic.png"),
    ("[就这？]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16164186362506_pic.png"),
    ("[绿帽]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16164186706521_pic.png"),
    ("[吐彩]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16164187059048_pic.png"),
    ("[下饭]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16164187375310_pic.png"),
    ("[艺术]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_dynamic_long_material_16164191102931_pic.png"),
    ("[炸弹]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_dynamic_long_material_16164195401240_pic.png"),
    ("[有点6]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104410880430_pic.png"),
    ("[OK]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16100992014714_pic.png"),
    ("[爱心]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104371440086_pic.png"),
    ("[闭嘴吧你]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104372862317_pic.png"),
    ("[吃瓜]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104410395955_pic.png"),
    ("[哭唧唧]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104450655350_pic.png"),
    ("[哈哈大笑]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104451098331_pic.png"),
    ("[犯困]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104451513709_pic.png"),
    ("[扶额头]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104453003643_pic.png"),
    ("[做鬼脸]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104452640866_pic.png"),
    ("[脸红]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104453501179_pic.png"),
    ("[汗颜]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104454647250_pic.png"),
    ("[嘿嘿嘿]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16117350008059_pic.png"),
    ("[哼]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104455595101_pic.png"),
    ("[奸诈地笑]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104456229242_pic.png"),
    ("[惊吓]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104456821101_pic.png"),
    ("[可可爱爱]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104457384583_pic.png"),
    ("[酷哦]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104458147877_pic.png"),
    ("[裂开了]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104458758417_pic.png"),
    ("[流泪]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104459270039_pic.png"),
    ("[么么哒]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104459735817_pic.png"),
    ("[求抱抱]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16121516366022_pic.png"),
    ("[让我看看]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104460734642_pic.png"),
    ("[社会社会]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104461339798_pic.png"),
    ("[生病]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104461844202_pic.png"),
    ("[死亡]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104462242127_pic.png"),
    ("[叹气]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104463504539_pic.png"),
    ("[捂嘴笑]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104463199182_pic.png"),
    ("[哇哦]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104463996175_pic.png"),
    ("[委屈]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104464321302_pic.png"),
    ("[吓]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104464681778_pic.png"),
    ("[笑哭了]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104465074565_pic.png"),
    ("[有点疑问]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16104465428478_pic.png"),
    ("[不错哦]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_dynamic_long_material_16152729422826_pic.png"),
    ("[超级6]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_dynamic_long_material_16152729800539_pic.png"),
    ("[奥利给]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_dynamic_long_material_16152730599690_pic.png"),
    ("[哭哭哭]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_dynamic_long_material_16152730951224_pic.png"),
    ("[毒奶]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_dynamic_long_material_16152731234493_pic.png"),
    ("[真香]", "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_dynamic_long_material_16152731527101_pic.png"),
    ("[动漫哇]", "https://materials-g-ai.msstatic.com/banshen/prod/banshen_00226/stickers/aiwa/aiwa%4056x48.png"),
    ("[动漫爱心]", "https://materials-g-ai.msstatic.com/banshen/prod/banshen_00226/stickers/aiax/aiax%4056x48.png"),
    ("[动漫委屈]", "https://materials-g-ai.msstatic.com/banshen/prod/banshen_00226/stickers/aiwq/aiwq%4056x48.png"),
    ("[动漫生气]", "https://materials-g-ai.msstatic.com/banshen/prod/banshen_00226/stickers/aisq/aisq%4056x48.png"),
    ("[动漫坏笑]", "https://materials-g-ai.msstatic.com/banshen/prod/banshen_00226/stickers/aihx/aihx%4056x48.png"),
    ("[动漫害羞]", "https://materials-g-ai.msstatic.com/banshen/prod/banshen_00226/stickers/aixx/aixx%4056x48.png"),
    ("[动漫困困]", "https://materials-g-ai.msstatic.com/banshen/prod/banshen_00226/stickers/aiku/aiku%4056x48.png"),
];

/// 从弹幕正文提取表情包；无命中 -> `None`。
pub fn extract_emoticons(content: &str) -> Option<Vec<LiveMessageEmoticon>> {
    let mut found: Vec<LiveMessageEmoticon> = Vec::new();
    for token in bracket_tokens(content) {
        // 表键是 `[xxx]`（含方括号）形态，与 Dart `m.group(0)` 一致
        let Some(url) = lookup(&format!("[{token}]")) else {
            continue;
        };
        // Dart 用 `m.group(0)` 作为 name —— **含方括号**（表键也是 `[xxx]` 形态）
        found.push(LiveMessageEmoticon {
            name: Some(format!("[{token}]")),
            url: url.to_string(),
            width: None,
            height: None,
            large: false,
            emoticon_unique: None,
        });
    }
    if found.is_empty() {
        None
    } else {
        Some(found)
    }
}

/// 查表（线性扫描：表为构建期常量，单条弹幕最多 16 字符）。
fn lookup(token: &str) -> Option<&'static str> {
    HUYA_EMOTICONS
        .iter()
        .find(|(name, _)| *name == token)
        .map(|(_, url)| *url)
}

/// 扫描 `[...]` 占位符（1..=16 字符，内部不含方括号 —— 对齐 Dart 正则）。
///
/// 手写扫描而非正则 crate：逻辑极简且避免在热路径上编译正则。
fn bracket_tokens(content: &str) -> Vec<&str> {
    let bytes = content.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] != b'[' {
            i += 1;
            continue;
        }
        let start = i + 1;
        let mut j = start;
        while j < bytes.len() && bytes[j] != b'[' && bytes[j] != b']' {
            j += 1;
        }
        // `[` 之后必须紧跟 `]`（无嵌套），且长度 1..=16
        if j < bytes.len() && bytes[j] == b']' && start < j && (j - start) <= 16 {
            if let Some(token) = content.get(start..j) {
                if !token.is_empty() {
                    out.push(token);
                }
            }
            i = j + 1;
        } else {
            i = start;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn table_size_matches_dart_source() {
        assert_eq!(HUYA_EMOTICONS.len(), 97, "表情数量与 Dart 侧一致");
    }

    #[test]
    fn extracts_known_emoticon_from_text() {
        let got = extract_emoticons("牛啊[666]").expect("应提取到表情");
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].name.as_deref(), Some("[666]"), "Dart 用 group(0) 作 name，含方括号");
        assert!(got[0].url.ends_with("_pic.png"), "实际 {}", got[0].url);
        assert!(!got[0].large);
    }

    #[test]
    fn extracts_multiple_and_keeps_order() {
        let got = extract_emoticons("[666]打[滑稽]").expect("应提取到两个");
        let names: Vec<&str> = got.iter().filter_map(|e| e.name.as_deref()).collect();
        assert_eq!(names, vec!["[666]", "[滑稽]"]);
    }

    #[test]
    fn unknown_and_plain_brackets_are_skipped() {
        assert!(extract_emoticons("[这不是表情]").is_none(), "表外占位符跳过");
        assert!(extract_emoticons("[嵌套[括号]]").is_none(), "嵌套括号不提取");
        assert!(extract_emoticons("[]").is_none(), "空括号不提取");
        assert!(
            extract_emoticons(&format!("[{}]", "长".repeat(17))).is_none(),
            "超长占位符不提取"
        );
    }

    #[test]
    fn duplicate_tokens_are_all_kept() {
        // 对齐 Dart：allMatches 不去重，重复出现即重复产出
        let got = extract_emoticons("[666][666]").expect("应提取到两个");
        assert_eq!(got.len(), 2);
    }

    #[test]
    fn plain_text_without_brackets_returns_none() {
        assert!(extract_emoticons("纯文本").is_none());
    }
}
