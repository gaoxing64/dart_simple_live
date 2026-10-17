//! 直播间 URL → (平台, 房间标识) 解析。
//!
//! 只认主播页地址，不做短链跳转（与已被删除的 Dart `simple_live_console` 同一口径）。
//! 接受带 scheme 或裸域名两种写法：`live.bilibili.com/7734200` / `https://live.bilibili.com/7734200`。

/// 支持的平台。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    Bilibili,
    Douyu,
    Huya,
    Douyin,
    Twitch,
}

impl Platform {
    /// 站点显示名（与 core 各 `*Site::name()` 的返回值一致；供错误提示使用）。
    #[allow(dead_code)]
    pub fn name(self) -> &'static str {
        match self {
            Platform::Bilibili => "哔哩哔哩直播",
            Platform::Douyu => "斗鱼直播",
            Platform::Huya => "虎牙直播",
            Platform::Douyin => "抖音直播",
            Platform::Twitch => "Twitch",
        }
    }
}

/// 解析结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Target {
    /// 平台。
    pub platform: Platform,
    /// 房间标识：B站为房间号、斗鱼/虎牙为房间号、抖音为 web_rid、Twitch 为频道名。
    pub room: String,
}

/// 解析直播间地址。
///
/// 顺序敏感：`live.douyin.com` 含 `douyin.com` 子串，故先匹配更具体的域名。
pub fn parse(raw: &str) -> Result<Target, String> {
    let url = raw.trim();
    if url.is_empty() {
        return Err("URL 不能为空".to_string());
    }

    let table: &[(&str, Platform)] = &[
        ("live.bilibili.com", Platform::Bilibili),
        ("bilibili.com", Platform::Bilibili),
        ("huya.com", Platform::Huya),
        ("douyu.com", Platform::Douyu),
        ("live.douyin.com", Platform::Douyin),
        ("douyin.com", Platform::Douyin),
        ("twitch.tv", Platform::Twitch),
    ];

    for (needle, platform) in table {
        if url.contains(needle) {
            let room = match segment_after(url, needle) {
                Some(room) => room,
                None => {
                    return Err(format!(
                        "无法从地址中取到房间标识：{url}（应形如 https://{needle}/<房间号>）"
                    ))
                }
            };
            return Ok(Target {
                platform: *platform,
                room,
            });
        }
    }

    Err(format!(
        "暂不支持该站点：{url}（支持 B站/斗鱼/虎牙/抖音/Twitch）"
    ))
}

/// 取 `marker` 之后的第一个路径段，剥掉 query / fragment / 尾斜杠。
fn segment_after(url: &str, marker: &str) -> Option<String> {
    let idx = url.find(marker)? + marker.len();
    let rest = &url[idx..];
    let rest = rest.split(['?', '#']).next().unwrap_or("");
    let seg = rest
        .trim_start_matches('/')
        .split('/')
        .next()
        .unwrap_or("")
        .trim();
    if seg.is_empty() {
        None
    } else {
        Some(seg.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_all_supported_hosts() {
        let cases = [
            ("https://live.bilibili.com/7734200", Platform::Bilibili, "7734200"),
            ("live.bilibili.com/6", Platform::Bilibili, "6"),
            ("https://www.huya.com/lpl", Platform::Huya, "lpl"),
            ("https://www.douyu.com/9999", Platform::Douyu, "9999"),
            ("https://live.douyin.com/416144012050", Platform::Douyin, "416144012050"),
            ("https://www.twitch.tv/shroud", Platform::Twitch, "shroud"),
        ];
        for (url, platform, room) in cases {
            let t = parse(url).unwrap();
            assert_eq!(t.platform, platform, "{url}");
            assert_eq!(t.room, room, "{url}");
        }
    }

    #[test]
    fn strips_query_and_fragment() {
        let t = parse("https://live.bilibili.com/7734200?broadcast_type=0#x").unwrap();
        assert_eq!(t.room, "7734200");
    }

    #[test]
    fn rejects_unknown_or_empty() {
        assert!(parse("").is_err());
        assert!(parse("https://example.com/1").is_err());
        assert!(parse("https://live.bilibili.com/").is_err());
    }
}
