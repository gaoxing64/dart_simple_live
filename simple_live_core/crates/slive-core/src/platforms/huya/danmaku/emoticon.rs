//! 虎牙弹幕表情包表。
//!
//! 静态表（[`HUYA_EMOTICONS`]）是历史 97 项小表情，作为 API 失败时的兜底；
//! 线上另有大表情 / 梗表情包（`iType=2/3`）：由
//! `wupui/getExpressionEmoticonPackage` 按房间 `lPid` 拉取（见
//! [`super::super::tup::fetch_emoticon_table`]），`sFlexiUrl` 的 `steam.png`
//! 换成 `steam_3.png` 即大图。动态表会覆盖同名静态项，未命中的静态项保留。
//!
//! 提取规则（对齐 Dart `_getHuyaEmoticonsFromContent`）：
//! 以 `\[[^\[\]]{1,16}\]` 语义扫描正文，命中表内的占位符转 [`LiveMessageEmoticon`]；
//! 未命中表（正文字面量）跳过；结果为空 -> `None`（不返回空数组）。

use std::collections::HashMap;

use once_cell::sync::Lazy;

use crate::models::LiveMessageEmoticon;

use super::tars_emoticon::ExpressionEmoticonPackage;

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

/// 单个表情的展示信息。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HuyaEmoticon {
    /// 图片地址（已统一 https）。
    pub url: String,
    /// 是否按大表情渲染（梗表情 / itai大表情）。
    pub large: bool,
}

/// 表情码 -> 展示信息。
pub type HuyaEmoticonTable = HashMap<String, HuyaEmoticon>;

/// 网页端全局包的稳定 id。
///
/// 只用于合并时的优先级（全局包先应用、房间包最后覆盖），**不是过滤器**：
/// 未列出的包仍会正常合并；新出现的全局包会被当作更具体的包处理。
const GLOBAL_PACKAGE_IDS: &[&str] = &["1", "165", "229", "243", "377", "939", "945"];

fn is_global_package(package: &ExpressionEmoticonPackage) -> bool {
    GLOBAL_PACKAGE_IDS.contains(&package.s_package_id.as_str())
}

/// 静态 97 项表（API 失败时的兜底）。
pub fn static_table() -> HuyaEmoticonTable {
    HUYA_EMOTICONS
        .iter()
        .map(|(name, url)| {
            (
                (*name).to_string(),
                HuyaEmoticon {
                    url: (*url).to_string(),
                    large: false,
                },
            )
        })
        .collect()
}

static STATIC_TABLE: Lazy<HuyaEmoticonTable> = Lazy::new(static_table);

/// 静态表引用（`run_session` 默认口径）。
pub fn static_emoticons() -> &'static HuyaEmoticonTable {
    &STATIC_TABLE
}

/// 把 API 包合并进静态表；动态项覆盖同名静态项。
///
/// 锁定 / 付费包也合并：只影响「能否发送」，不影响已收到消息的图片展示；
/// 服务端返回量有界（数百项），不再额外截断。
pub fn build_table(packages: &[ExpressionEmoticonPackage]) -> HuyaEmoticonTable {
    let mut table = static_table();
    // 全局包先应用，房间专属包最后覆盖同名码（API 的 vPackage 顺序不保证这一点；
    // 房间包可能是 type 2 也可能是 type 3，不能只看 type）。
    let mut ordered: Vec<&ExpressionEmoticonPackage> = packages.iter().collect();
    ordered.sort_by_key(|package| (!is_global_package(package), package.i_type));
    for package in ordered {
        for emoticon in &package.v_emoticon {
            let name = emoticon.s_name.trim();
            if !(name.starts_with('[') && name.ends_with(']')) || name.len() < 3 {
                continue;
            }
            let (url, large) = if emoticon.i_type >= 2 {
                match large_flexi_url(&emoticon.s_flexi_url) {
                    Some(url) => (url, true),
                    None => match normalize_url(&emoticon.s_url) {
                        Some(url) => (url, false),
                        None => continue,
                    },
                }
            } else {
                // 优先动态图；extra 非法/为空时仍要回退到静态 sUrl。
                match normalize_url(&emoticon.s_extra_url).or_else(|| normalize_url(&emoticon.s_url)) {
                    Some(url) => (url, false),
                    None => continue,
                }
            };
            table.insert(name.to_string(), HuyaEmoticon { url, large });
        }
    }
    table
}

/// 大表情素材：API 给的是 `steam.png`，实际大图是同目录 `steam_3.png`。
pub fn large_flexi_url(raw: &str) -> Option<String> {
    let url = normalize_url(raw)?;
    if url.ends_with("steam.png") {
        return Some(format!("{}_3.png", url.trim_end_matches(".png")));
    }
    Some(url)
}

/// 统一升 https；空 / 非 http(s) 地址返回 `None`。
fn normalize_url(raw: &str) -> Option<String> {
    let url = raw.trim();
    if url.is_empty() {
        return None;
    }
    if let Some(rest) = url.strip_prefix("http://") {
        return Some(format!("https://{rest}"));
    }
    if url.starts_with("https://") {
        return Some(url.to_string());
    }
    if let Some(rest) = url.strip_prefix("//") {
        return Some(format!("https://{rest}"));
    }
    None
}

/// 从弹幕正文提取表情包；无命中 -> `None`（使用静态表）。
pub fn extract_emoticons(content: &str) -> Option<Vec<LiveMessageEmoticon>> {
    extract_emoticons_with(content, &STATIC_TABLE)
}

/// 从弹幕正文提取表情包；`table` 由会话按房间动态注入。
pub fn extract_emoticons_with(
    content: &str,
    table: &HuyaEmoticonTable,
) -> Option<Vec<LiveMessageEmoticon>> {
    let mut found: Vec<LiveMessageEmoticon> = Vec::new();
    for token in bracket_tokens(content) {
        // 表键是 `[xxx]`（含方括号）形态，与 Dart `m.group(0)` 一致
        let key = format!("[{token}]");
        let Some(emoticon) = table.get(&key) else {
            continue;
        };
        // Dart 用 `m.group(0)` 作为 name —— **含方括号**（表键也是 `[xxx]` 形态）
        found.push(LiveMessageEmoticon {
            name: Some(key),
            url: emoticon.url.clone(),
            width: None,
            height: None,
            large: emoticon.large,
            emoticon_unique: None,
        });
    }
    if found.is_empty() {
        None
    } else {
        Some(found)
    }
}

/// 扫描 `[...]` 占位符（1..=16 个 UTF-16 码元，内部不含方括号 —— 对齐 Dart 正则）。
///
/// ⚠️ 上限必须按 UTF-16 码元而不是 UTF-8 字节：`[勇敢牛牛不怕困难]` 是 8 个
/// 汉字、24 个 UTF-8 字节，按字节卡 16 会把真实大表情码整批漏掉。
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
        // `[` 之后必须紧跟 `]`（无嵌套），且长度 1..=16 个 UTF-16 码元
        if j < bytes.len() && bytes[j] == b']' && start < j {
            if let Some(token) = content.get(start..j) {
                if !token.is_empty() && token.encode_utf16().count() <= 16 {
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

    #[test]
    fn large_flexi_url_switches_to_3x_asset() {
        assert_eq!(
            large_flexi_url("https://fileserver.cdn.huya.com/a/expressconfig/steam.png")
                .as_deref(),
            Some("https://fileserver.cdn.huya.com/a/expressconfig/steam_3.png")
        );
        assert_eq!(
            large_flexi_url("https://fileserver.cdn.huya.com/a/expressconfig/steam_3.png")
                .as_deref(),
            Some("https://fileserver.cdn.huya.com/a/expressconfig/steam_3.png")
        );
        assert!(large_flexi_url("").is_none());
    }

    #[test]
    fn build_table_merges_room_large_emotes() {
        use super::super::tars_emoticon::{
            ExpressionEmoticon, ExpressionEmoticonPackage,
        };

        let package = ExpressionEmoticonPackage {
            v_emoticon: vec![
                ExpressionEmoticon {
                    s_name: "[墨镜小哥]".to_string(),
                    i_type: 3,
                    s_flexi_url:
                        "https://fileserver.cdn.huya.com/a/expressconfig/steam.png".to_string(),
                    ..Default::default()
                },
                ExpressionEmoticon {
                    s_name: "[不错哦]".to_string(),
                    i_type: 0,
                    s_url: "http://cdn/static.png".to_string(),
                    s_extra_url: "http://cdn/dynamic.png".to_string(),
                    ..Default::default()
                },
                ExpressionEmoticon {
                    s_name: "[坏extra]".to_string(),
                    i_type: 0,
                    s_url: "https://cdn/ok.png".to_string(),
                    s_extra_url: "ftp://bad".to_string(),
                    ..Default::default()
                },
            ],
            ..Default::default()
        };
        let table = build_table(&[package]);
        assert!(table.contains_key("[666]"), "静态项必须保留");

        let large = table.get("[墨镜小哥]").expect("应合入房间大表情");
        assert_eq!(
            large.url,
            "https://fileserver.cdn.huya.com/a/expressconfig/steam_3.png"
        );
        assert!(large.large);

        let small = table.get("[不错哦]").expect("应合入小表情");
        assert_eq!(small.url, "https://cdn/dynamic.png", "优先用动态地址");
        assert!(!small.large);

        let fallback = table.get("[坏extra]").expect("extra 非法时应回退 sUrl");
        assert_eq!(fallback.url, "https://cdn/ok.png");
    }

    #[test]
    fn room_specific_package_wins_on_code_collision() {
        use super::super::tars_emoticon::{
            ExpressionEmoticon, ExpressionEmoticonPackage,
        };

        let global = ExpressionEmoticonPackage {
            i_type: 0,
            v_emoticon: vec![ExpressionEmoticon {
                s_name: "[666]".to_string(),
                s_url: "https://global/666.png".to_string(),
                ..Default::default()
            }],
            ..Default::default()
        };
        let room = ExpressionEmoticonPackage {
            i_type: 3,
            v_emoticon: vec![ExpressionEmoticon {
                s_name: "[666]".to_string(),
                i_type: 3,
                s_flexi_url: "https://room/expressconfig/steam.png".to_string(),
                ..Default::default()
            }],
            ..Default::default()
        };
        // 故意把房间包放在前面：排序后仍应由 type=3 覆盖 type=0。
        let table = build_table(&[room, global]);
        let emoticon = table.get("[666]").expect("应有 [666]");
        assert_eq!(emoticon.url, "https://room/expressconfig/steam_3.png");
        assert!(emoticon.large);
    }

    #[test]
    fn room_type2_package_wins_over_global_type2() {
        use super::super::tars_emoticon::{
            ExpressionEmoticon, ExpressionEmoticonPackage,
        };

        let global = ExpressionEmoticonPackage {
            s_package_id: "377".to_string(),
            i_type: 2,
            v_emoticon: vec![ExpressionEmoticon {
                s_name: "[同名梗]".to_string(),
                i_type: 2,
                s_flexi_url: "https://global/expressconfig/steam.png".to_string(),
                ..Default::default()
            }],
            ..Default::default()
        };
        let room = ExpressionEmoticonPackage {
            s_package_id: "637".to_string(),
            i_type: 2,
            v_emoticon: vec![ExpressionEmoticon {
                s_name: "[同名梗]".to_string(),
                i_type: 2,
                s_flexi_url: "https://room/expressconfig/steam.png".to_string(),
                ..Default::default()
            }],
            ..Default::default()
        };
        // 房间包即使出现在 global 后面、且同为 type=2，也必须最后覆盖。
        let table = build_table(&[global, room]);
        let emoticon = table.get("[同名梗]").expect("应有 [同名梗]");
        assert_eq!(emoticon.url, "https://room/expressconfig/steam_3.png");
        assert!(emoticon.large);
    }

    #[test]
    fn extract_emoticons_handles_long_chinese_codes() {
        // 8 个汉字 = 24 个 UTF-8 字节；上限必须按 UTF-16 码元算，否则真实码被漏掉。
        let mut table = static_table();
        table.insert(
            "[勇敢牛牛不怕困难]".to_string(),
            HuyaEmoticon {
                url: "https://x/long.png".to_string(),
                large: false,
            },
        );
        let got = extract_emoticons_with("[勇敢牛牛不怕困难]", &table).expect("长中文码应能提取");
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].name.as_deref(), Some("[勇敢牛牛不怕困难]"));
    }

    #[test]
    fn extract_emoticons_with_uses_dynamic_table() {
        let mut table = static_table();
        table.insert(
            "[墨镜小哥]".to_string(),
            HuyaEmoticon {
                url: "https://x/steam_3.png".to_string(),
                large: true,
            },
        );
        let got = extract_emoticons_with("[墨镜小哥]666", &table).expect("应提取到大表情");
        assert_eq!(got[0].name.as_deref(), Some("[墨镜小哥]"));
        assert!(got[0].large);
    }
}
