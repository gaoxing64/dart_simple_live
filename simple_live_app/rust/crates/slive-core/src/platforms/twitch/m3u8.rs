//! Twitch m3u8 主播放列表解析（对照 `twitch_site.dart:136-176`）。
//!
//! Dart 的做法是**纯文本扫描**（无 m3u8 库）：
//! 1. 逐行取以 `https://` 开头的行作为播放地址；
//! 2. 若一条都没有（相对路径场景），退化为取以 `m3u8` 结尾的行；
//! 3. 用 `BANDWIDTH=(\d+)` 抓全部带宽，按**出现顺序**与地址一一对应；
//! 4. 按带宽降序排序，映射为清晰度名。
//!
//! 本模块保持同一算法与同一顺序语义（Rust `sort_by` 为稳定排序，Dart `List.sort` 亦然），
//! 便于与 Dart 行为逐条对齐。

/// 一条播放线路（地址 + 带宽）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Variant {
    /// 播放地址。
    pub url: String,
    /// 带宽（bps）；缺失时为 0。
    pub bandwidth: i64,
}

/// 解析 m3u8 主播放列表，返回按带宽降序的线路列表。
pub fn parse_variants(content: &str) -> Vec<Variant> {
    let mut urls: Vec<String> = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("https://") {
            urls.push(trimmed.to_string());
        }
    }
    if urls.is_empty() {
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.ends_with("m3u8") {
                urls.push(trimmed.to_string());
            }
        }
    }
    if urls.is_empty() {
        return Vec::new();
    }

    let bandwidths = all_bandwidths(content);
    let mut variants: Vec<Variant> = urls
        .into_iter()
        .enumerate()
        .map(|(index, url)| Variant {
            url,
            bandwidth: bandwidths.get(index).copied().unwrap_or(0),
        })
        .collect();
    // 稳定排序 + 降序，与 Dart 的 `_playUrlList.sort((a,b) => bw[b]-bw[a])` 等价。
    // `sort_by_key(|v| Reverse(v.bandwidth))` 保持稳定排序语义（同带宽保持出现顺序）。
    variants.sort_by_key(|variant| std::cmp::Reverse(variant.bandwidth));
    variants
}

/// 抓取全部 `BANDWIDTH=<digits>`（出现顺序）。
fn all_bandwidths(content: &str) -> Vec<i64> {
    let mut out = Vec::new();
    let mut rest = content;
    while let Some(pos) = rest.find("BANDWIDTH=") {
        let after = &rest[pos + "BANDWIDTH=".len()..];
        let digits: String = after.chars().take_while(char::is_ascii_digit).collect();
        if digits.is_empty() {
            // 无数字：跳到下一个出现位置，避免死循环。
            rest = &after[1..];
            continue;
        }
        out.push(digits.parse::<i64>().unwrap_or(0));
        rest = after;
    }
    out
}

/// 带宽 -> 清晰度名（对照 `twitch_site.dart:182-188` `_getQualityName`，阈值逐条对齐）。
pub fn quality_name(bandwidth: i64) -> &'static str {
    if bandwidth > 5_000_000 {
        "1080P"
    } else if bandwidth > 2_500_000 {
        "720P"
    } else if bandwidth > 1_000_000 {
        "480P"
    } else if bandwidth > 500_000 {
        "360P"
    } else {
        "自动"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MASTER: &str = r#"#EXTM3U
#EXT-X-TWITCH-INFO:NODE="video-edge-1.abs.hls.ttvnw.net",TRANSCODESTACK="2025TranscodeX264_v2"
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="chunked",NAME="1080p60",AUTOSELECT=YES,DEFAULT=YES
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS="avc1.64002A,mp4a.40.2"
https://video-edge-1.abs.hls.ttvnw.net/v1/segment/CAAAAAAAAAAA-index-dvr.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720
https://video-edge-2.abs.hls.ttvnw.net/v1/segment/CAAAAAAAAAAA-index-dvr.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
https://video-edge-3.abs.hls.ttvnw.net/v1/segment/CAAAAAAAAAAA-index-dvr.m3u8
"#;

    #[test]
    fn parses_and_sorts_by_bandwidth_desc() {
        let got = parse_variants(MASTER);
        assert_eq!(got.len(), 3);
        assert_eq!(got[0].bandwidth, 6_000_000);
        assert_eq!(got[1].bandwidth, 3_000_000);
        assert_eq!(got[2].bandwidth, 800_000);
        assert!(got[0].url.contains("video-edge-1"));
        assert!(got[2].url.contains("video-edge-3"));
    }

    #[test]
    fn falls_back_to_m3u8_suffix_when_no_https_line() {
        let got = parse_variants(
            "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1200000\nchunk/index-dvr.m3u8\n",
        );
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].url, "chunk/index-dvr.m3u8");
        assert_eq!(got[0].bandwidth, 1_200_000);
    }

    #[test]
    fn missing_bandwidth_defaults_to_zero_and_sorts_last() {
        let got = parse_variants("#EXTM3U\nhttps://a/1.m3u8\nhttps://b/2.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=900000\n");
        assert_eq!(got.len(), 2);
        assert_eq!(got[0].bandwidth, 900_000, "有带宽的排前");
        assert_eq!(got[1].bandwidth, 0, "无带宽的兜底 0，排最后");
    }

    #[test]
    fn empty_playlist_yields_no_variants() {
        assert!(parse_variants("#EXTM3U\n").is_empty());
    }

    #[test]
    fn quality_name_thresholds_match_dart() {
        assert_eq!(quality_name(6_000_000), "1080P");
        assert_eq!(quality_name(5_000_001), "1080P");
        assert_eq!(quality_name(5_000_000), "720P");
        assert_eq!(quality_name(2_500_001), "720P");
        assert_eq!(quality_name(2_500_000), "480P");
        assert_eq!(quality_name(1_000_001), "480P");
        assert_eq!(quality_name(1_000_000), "360P");
        assert_eq!(quality_name(500_001), "360P");
        assert_eq!(quality_name(500_000), "自动");
        assert_eq!(quality_name(0), "自动");
    }
}
