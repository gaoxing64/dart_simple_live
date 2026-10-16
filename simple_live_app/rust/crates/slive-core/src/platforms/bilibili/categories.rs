//! F-01 分类 A 列表（对照 `bilibili_site.dart:51-80`，DTV 无蓝本，必须从 Dart core 重实现）。

use serde_json::Value;

use crate::error::SliveError;
use crate::http::check_api_code;
use crate::models::{LiveCategory, LiveSubCategory};

use super::site::BilibiliSite;
use super::util::text;

const URL: &str = "https://api.live.bilibili.com/room/v1/Area/getList";

/// 拉取分类（`need_entrance=1, parent_id=0`）。
pub(crate) async fn fetch(site: &BilibiliSite) -> Result<Vec<LiveCategory>, SliveError> {
    let query = vec![
        ("need_entrance".to_string(), "1".to_string()),
        ("parent_id".to_string(), "0".to_string()),
    ];
    let value = site.get_json(URL, query).await?;
    check_api_code(&value)?;
    Ok(parse(&value))
}

/// 解析分类树；`data` 缺失/非数组 -> 空列表（AC-27）。
pub(crate) fn parse(value: &Value) -> Vec<LiveCategory> {
    crate::util::array_at(value, "/data")
        .iter()
        .map(|item| LiveCategory {
            name: text(item, "name"),
            id: text(item, "id"),
            children: crate::util::array_at(item, "/list").iter().map(parse_sub).collect(),
        })
        .collect()
}

fn parse_sub(item: &Value) -> LiveSubCategory {
    LiveSubCategory {
        name: text(item, "name"),
        // Dart: `"${pic ?? ""}@100w.png"` -> 始终追加后缀（AC-01）。
        pic: Some(format!("{}@100w.png", text(item, "pic"))),
        id: text(item, "id"),
        parent_id: text(item, "parent_id"),
    }
}
