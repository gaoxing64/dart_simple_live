//! AC-21：wbi 签名 golden 夹具驱动断言。
//!
//! golden（`golden-wbi.json`）由独立推导产生（QA 算法推导 + 第三方 Python 实现交叉验证），
//! 实现者不得修改夹具 —— AC-35「不自证」。

mod common;

use serde_json::Value;
use slive_core::wbi::{get_mixin_key, get_wbi_sign};

/// 把夹具里的 params（含 wts）转成签名入参。
fn params_of(case: &Value, wts: &str) -> Vec<(String, String)> {
    let mut params: Vec<(String, String)> = case["params_before_sign"]
        .as_object()
        .expect("params_before_sign")
        .iter()
        .map(|(k, v)| (k.clone(), v.as_str().expect("字符串参数").to_string()))
        .collect();
    params.push(("wts".to_string(), wts.to_string()));
    params
}

#[test]
fn ac21_main_case_matches_golden() {
    let golden: Value =
        serde_json::from_str(&common::read_text("golden/golden-wbi.json")).expect("解析 golden");
    let img = golden["input"]["img_key"].as_str().expect("img_key");
    let sub = golden["input"]["sub_key"].as_str().expect("sub_key");
    let wts = golden["input"]["wts"].as_str().expect("wts");
    let expect = &golden["expect"];

    assert_eq!(
        get_mixin_key(&format!("{img}{sub}")),
        expect["mixin_key"].as_str().expect("mixin_key"),
        "mixin key 与 golden 不符"
    );

    let params = params_of(&golden["input"], wts);
    assert_eq!(
        slive_core::wbi::build_signing_query(&params),
        expect["query"].as_str().expect("query"),
        "签名 query（排序/过滤/编码）与 golden 不符"
    );
    assert_eq!(
        get_wbi_sign(&params, &get_mixin_key(&format!("{img}{sub}"))),
        expect["w_rid"].as_str().expect("w_rid"),
        "w_rid 与 golden 不符"
    );
}

#[test]
fn ac21_extra_case_sorting_filtering_encoding() {
    let golden: Value =
        serde_json::from_str(&common::read_text("golden/golden-wbi.json")).expect("解析 golden");
    let case = &golden["extra_case"];
    let img = golden["input"]["img_key"].as_str().expect("img_key");
    let sub = golden["input"]["sub_key"].as_str().expect("sub_key");
    let wts = case["wts"].as_str().expect("wts");
    let mixin = get_mixin_key(&format!("{img}{sub}"));

    let params = params_of(case, wts);
    assert_eq!(
        slive_core::wbi::build_signing_query(&params),
        case["query"].as_str().expect("query"),
        "排序 + 过滤 + 空格编码路径与 golden 不符"
    );
    assert_eq!(
        get_wbi_sign(&params, &mixin),
        case["w_rid"].as_str().expect("w_rid"),
        "extra case 的 w_rid 与 golden 不符"
    );
}
