//! 分类模型（对照 Dart `live_category.dart`）。

/// 一级分类（A 列表项）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveCategory {
    /// 分类名。
    pub name: String,
    /// 分类 ID（字符串形态，对齐 Dart）。
    pub id: String,
    /// 子分类。
    pub children: Vec<LiveSubCategory>,
}

/// 二级分类。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LiveSubCategory {
    /// 分类名。
    pub name: String,
    /// 分类图标（可为空）。
    pub pic: Option<String>,
    /// 分类 ID。
    pub id: String,
    /// 父分类 ID。
    pub parent_id: String,
}
