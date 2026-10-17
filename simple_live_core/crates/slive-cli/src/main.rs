//! `slive` —— Simple Live 命令行工具。
//!
//! 直连 `slive-core`（不经 flutter_rust_bridge），因此可做纯 Rust 单文件分发。

mod danmaku;
mod url;
mod ws;

use std::collections::HashMap;

use async_trait::async_trait;
use slive_core::error::SliveError;
use slive_core::models::{LivePlayQuality, LivePlayUrl, LiveRoomDetail};
use slive_core::platforms::bilibili::BilibiliSite;
use slive_core::platforms::douyin::DouyinSite;
use slive_core::platforms::douyu::DouyuSite;
use slive_core::platforms::huya::HuyaSite;
use slive_core::platforms::twitch::TwitchSite;

use url::{Platform, Target};

const HELP: &str = "\
slive —— Simple Live 命令行工具

用法:
  slive info <URL> [-q <清晰度>] [--all]   获取房间信息与播放直链
  slive danmaku <URL> [--no-color]         持续输出弹幕（Ctrl-C 退出）
  slive help                               显示本帮助

支持站点:
  B站     https://live.bilibili.com/<房间号>
  斗鱼    https://www.douyu.com/<房间号>
  虎牙    https://www.huya.com/<房间号>
  抖音    https://live.douyin.com/<web_rid>
  Twitch  https://www.twitch.tv/<频道名>

选项:
  -q, --quality <名称>  仅取指定清晰度的直链（名称可为片段，如 原画）
      --all             取全部清晰度的直链（默认为最高档）
      --no-color        弹幕不输出 ANSI 颜色

示例:
  slive info https://live.bilibili.com/7734200
  slive info https://www.douyu.com/9999 -q 蓝光
  slive danmaku https://live.bilibili.com/6
";

#[tokio::main]
async fn main() {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    if let Err(message) = dispatch(&argv).await {
        eprintln!("错误：{message}");
        eprintln!("使用 `slive help` 查看用法。");
        std::process::exit(1);
    }
}

async fn dispatch(argv: &[String]) -> Result<(), String> {
    let Some(command) = argv.first().map(|s| s.as_str()) else {
        print!("{HELP}");
        return Ok(());
    };

    match command {
        "-h" | "--help" | "help" => {
            print!("{HELP}");
            return Ok(());
        }
        "info" | "i" | "danmaku" | "d" => {}
        other => return Err(format!("未知命令「{other}」")),
    }

    let mut positional: Vec<&str> = Vec::new();
    let mut quality: Option<String> = None;
    let mut all = false;
    let mut color = true;

    let mut index = 1;
    while index < argv.len() {
        match argv[index].as_str() {
            "-q" | "--quality" => {
                index += 1;
                quality = Some(
                    argv.get(index)
                        .ok_or("`--quality` 缺少参数")?
                        .to_string(),
                );
            }
            "--all" => all = true,
            "--no-color" => color = false,
            "-h" | "--help" => {
                print!("{HELP}");
                return Ok(());
            }
            other if other.starts_with('-') && other.len() > 1 => {
                return Err(format!("未知选项「{other}」"));
            }
            other => positional.push(other),
        }
        index += 1;
    }

    let raw = positional.first().ok_or("缺少直播间 URL")?;
    let target = url::parse(raw)?;

    match command {
        "info" | "i" => info(&target, quality.as_deref(), all).await,
        _ => {
            let site = build_site(target.platform);
            let detail = site
                .detail(target.room.clone())
                .await
                .map_err(|e| e.to_string())?;
            print_detail(&site, &detail);
            if !detail.status {
                return Err("房间未开播，无法获取弹幕".to_string());
            }
            println!("\n【开始获取弹幕】（Ctrl-C 退出）");
            danmaku::run(&target, &detail, color).await
        }
    }
}

async fn info(target: &Target, quality: Option<&str>, all: bool) -> Result<(), String> {
    let site = build_site(target.platform);
    let detail = site
        .detail(target.room.clone())
        .await
        .map_err(|e| e.to_string())?;
    print_detail(&site, &detail);

    if !detail.status {
        println!("\n房间未开播，无可用清晰度。");
        return Ok(());
    }

    let qualities = site
        .qualities(detail.clone())
        .await
        .map_err(|e| e.to_string())?;
    if qualities.is_empty() {
        println!("\n无可用清晰度。");
        return Ok(());
    }

    println!("\n可用清晰度：");
    for (index, item) in qualities.iter().enumerate() {
        println!("  【{}】{}", index + 1, item.quality);
    }

    let picked: Vec<LivePlayQuality> = if all {
        qualities.clone()
    } else if let Some(want) = quality {
        let exact: Vec<LivePlayQuality> = qualities
            .iter()
            .filter(|item| item.quality == want)
            .cloned()
            .collect();
        if !exact.is_empty() {
            exact
        } else {
            let fuzzy: Vec<LivePlayQuality> = qualities
                .iter()
                .filter(|item| item.quality.contains(want))
                .cloned()
                .collect();
            if fuzzy.is_empty() {
                return Err(format!("未找到清晰度「{want}」"));
            }
            fuzzy
        }
    } else {
        vec![qualities[0].clone()]
    };

    for item in picked {
        let play = site
            .urls(detail.clone(), item.clone())
            .await
            .map_err(|e| e.to_string())?;
        println!("\n直链（{}）：", item.quality);
        if play.urls.is_empty() {
            println!("  （无）");
        }
        for (index, line) in play.urls.iter().enumerate() {
            println!("  线路{}: {line}", index + 1);
        }
        print_headers(&play.headers);
    }

    Ok(())
}

fn print_detail(site: &Box<dyn SiteApi>, detail: &LiveRoomDetail) {
    println!("来源：{}", site.display_name());
    println!("房间号：{}", detail.room_id);
    println!("房间标题：{}", detail.title);
    println!("直播用户：{}", detail.user_name);
    println!("人气值：{}", detail.online);
    println!("状态：{}", if detail.status { "直播中" } else { "未开播" });
}

fn print_headers(headers: &Option<HashMap<String, String>>) {
    let Some(headers) = headers else {
        return;
    };
    if headers.is_empty() {
        return;
    }
    println!("  请求头：");
    for (key, value) in headers {
        println!("    {key}: {value}");
    }
}

fn build_site(platform: Platform) -> Box<dyn SiteApi> {
    match platform {
        Platform::Bilibili => Box::new(BilibiliSite::new()),
        Platform::Douyu => Box::new(DouyuSite::new()),
        Platform::Huya => Box::new(HuyaSite::new()),
        Platform::Douyin => Box::new(DouyinSite::new()),
        Platform::Twitch => Box::new(TwitchSite::new()),
    }
}

/// 五平台站点方法的统一视图。
///
/// 五个 `*Site` 的 `get_room_detail` / `get_play_qualities` / `get_play_urls`
/// 签名同构（owned 参数、同一组模型），故此处只做转发，不加任何逻辑。
#[async_trait]
trait SiteApi: Send + Sync {
    fn display_name(&self) -> String;
    async fn detail(&self, room_id: String) -> Result<LiveRoomDetail, SliveError>;
    async fn qualities(&self, detail: LiveRoomDetail) -> Result<Vec<LivePlayQuality>, SliveError>;
    async fn urls(
        &self,
        detail: LiveRoomDetail,
        quality: LivePlayQuality,
    ) -> Result<LivePlayUrl, SliveError>;
}

macro_rules! impl_site_api {
    ($site:ty) => {
        #[async_trait]
        impl SiteApi for $site {
            fn display_name(&self) -> String {
                <$site>::name(self)
            }

            async fn detail(&self, room_id: String) -> Result<LiveRoomDetail, SliveError> {
                <$site>::get_room_detail(self, room_id).await
            }

            async fn qualities(
                &self,
                detail: LiveRoomDetail,
            ) -> Result<Vec<LivePlayQuality>, SliveError> {
                <$site>::get_play_qualities(self, detail).await
            }

            async fn urls(
                &self,
                detail: LiveRoomDetail,
                quality: LivePlayQuality,
            ) -> Result<LivePlayUrl, SliveError> {
                <$site>::get_play_urls(self, detail, quality).await
            }
        }
    };
}

impl_site_api!(BilibiliSite);
impl_site_api!(DouyuSite);
impl_site_api!(HuyaSite);
impl_site_api!(DouyinSite);
impl_site_api!(TwitchSite);
