//! 虎牙的 Rust Core 模型翻译（纯逐字段映射，零协议逻辑 —— AC-39 / J-6）。
//!
//! 与共享的 `rust_site_models.dart` 分工：后者是B站**通用**模型（房间/分类/搜索/
//! 弹幕）的翻译，被四个平台复用；本文件只放**虎牙专属**的翻译需求：
//! - `LivePlayQuality.data` / `LiveRoomDetail.danmakuData` 的**透传**语义说明；
//! - `getSubCategories` 的列表映射（虎牙 core 有此扩展方法，B站没有）。
//!
//! 纪律：本文件**不出现** URL / 正则 / TARS / 字段计算；只做类型翻译。

import 'package:simple_live_core/src/rust/api/slive/models/category.dart'
    as rust_cat;
import 'package:simple_live_core/simple_live_core.dart';

/// 虎牙专属的模型翻译集合（纯静态函数）。
class RustHuyaModels {
  RustHuyaModels._();

  /// 子分类列表翻译（`getSubCategories` 返回值）。
  static List<LiveSubCategory> toCoreSubCategoryList(
          List<rust_cat.LiveSubCategory> items) =>
      items.map(toCoreSubCategory).toList();

  /// 单个子分类翻译。
  static LiveSubCategory toCoreSubCategory(rust_cat.LiveSubCategory v) =>
      LiveSubCategory(
        id: v.id,
        name: v.name,
        parentId: v.parentId,
        pic: v.pic,
      );
}