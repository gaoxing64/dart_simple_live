//! 签名用常量表（逐字节对照 Dart `abogus.dart`，改动须同步 Dart 侧）。
//!
//! 本文件是**纯数据**，不含逻辑；由 `ac_douyin_signature.rs` 的表维度测试守护
//! （256 项bigArray 全排列、两个 44 项 sortIndex 不越界）。

/// SM3 差分表：字节替换用的 256 项置换表（对齐 Dart `CryptoUtility.bigArray`）。
pub const BIG_ARRAY: [u8; 256] = [
    121, 243, 55, 234, 103, 36, 47, 228, 30, 231, 106, 6,
    115, 95, 78, 101, 250, 207, 198, 50, 139, 227, 220, 105,
    97, 143, 34, 28, 194, 215, 18, 100, 159, 160, 43, 8,
    169, 217, 180, 120, 247, 45, 90, 11, 27, 197, 46, 3,
    84, 72, 5, 68, 62, 56, 221, 75, 144, 79, 73, 161,
    178, 81, 64, 187, 134, 117, 186, 118, 16, 241, 130, 71,
    89, 147, 122, 129, 65, 40, 88, 150, 110, 219, 199, 255,
    181, 254, 48, 4, 195, 248, 208, 32, 116, 167, 69, 201,
    17, 124, 125, 104, 96, 83, 80, 127, 236, 108, 154, 126,
    204, 15, 20, 135, 112, 158, 13, 1, 188, 164, 210, 237,
    222, 98, 212, 77, 253, 42, 170, 202, 26, 22, 29, 182,
    251, 10, 173, 152, 58, 138, 54, 141, 185, 33, 157, 31,
    252, 132, 233, 235, 102, 196, 191, 223, 240, 148, 39, 123,
    92, 82, 128, 109, 57, 24, 38, 113, 209, 245, 2, 119,
    153, 229, 189, 214, 230, 174, 232, 63, 52, 205, 86, 140,
    66, 175, 111, 171, 246, 133, 238, 193, 99, 60, 74, 91,
    225, 51, 76, 37, 145, 211, 166, 151, 213, 206, 0, 200,
    244, 176, 218, 44, 184, 172, 49, 216, 93, 168, 53, 21,
    183, 41, 67, 85, 224, 155, 226, 242, 87, 177, 146, 70,
    190, 12, 162, 19, 137, 114, 25, 165, 163, 192, 23, 59,
    9, 94, 179, 107, 35, 7, 142, 131, 239, 203, 149, 136,
    61, 249, 14, 156,
];

/// 参与签名字节序列化的下标顺序（对齐 Dart `ABogus.sortIndex`）。
pub const SORT_INDEX: [usize; 44] = [
    18, 20, 52, 26, 30, 34, 58, 38, 40, 53, 42, 21,
    27, 54, 55, 31, 35, 57, 39, 41, 43, 22, 28, 32,
    60, 36, 23, 29, 33, 37, 44, 45, 59, 46, 47, 48,
    49, 50, 24, 25, 65, 66, 70, 71,
];

/// 参与 XOR 校验和的��标顺序（对齐 Dart `ABogus.sortIndex2`）。
pub const SORT_INDEX2: [usize; 44] = [
    18, 20, 26, 30, 34, 38, 40, 42,
    21, 27, 31, 35, 39, 41, 43, 22,
    28, 32, 36, 23, 29, 33, 37, 44,
    45, 46, 47, 48, 49, 50, 24, 25,
    52, 53, 54, 55, 57, 58, 59, 60,
    65, 66, 70, 71,
];

/// a_bogus 主字母表（对齐 Dart `ABogus.character`，64 字符）。
pub const CHARACTER: &str = "Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe";

/// UA 加密用的第二字母表（对齐 Dart `ABogus.character2`，64 字符）。
pub const CHARACTER2: &str = "ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe";

/// X-Bogus 字母表（对齐 Dart `xbogus.dart` 的 `xbogusAlphabet`）。
pub const XBOGUS_ALPHABET: &str = "Dkdpgh4ZKsQB80/Mfvw36XI1R25+WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe";

/// 标准 base64 字母表（X-Bogus 编码时作为中间索引层）。
pub const STANDARD_ALPHABET: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// 空串 MD5 的末两字节（对齐 Dart `xbogus.dart` 的 `emptyMd5Bytes`）。
pub const EMPTY_MD5_BYTES: [u8; 2] = [0x45, 0x3f];

/// 默认 UA（对齐 Dart `DouyinRequestParams.kDefaultUserAgent`）。
pub const DEFAULT_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0";

/// 默认浏览器指纹（对齐 Dart `BrowserFingerprintGenerator.generateFingerprint("Edge")`
/// 在 `innerWidth=1920/innerHeight=1080/screenY=30/sizeWidth=1920/sizeHeight=1080/
/// availWidth=1920/availHeight=1040` 时的输出）。
///
/// Dart 侧该值是**随机**的（`Random()`），此处固定为确定性默认值；
/// 平台侧若需随机化可自行生成同格式字符串并经`ABogus::with_fingerprint` 注入。
pub const DEFAULT_BROWSER_FP: &str = "1920|1080|1920|1040|0|30|0|0|1920|1080|1920|1040|1920|1080|24|24|Win32";

/// 默认 aid（对齐 Dart `ABogus.aid`）。
pub const DEFAULT_AID: u32 = 6383;

/// 默认 pageId（对齐 Dart `ABogus.pageId`）。
pub const DEFAULT_PAGE_ID: u32 = 0;

/// 默认盐值（对齐 Dart `ABogus.salt`）。
pub const SALT: &str = "cus";

/// UA 的 RC4 密钥（对齐 Dart `ABogus.uaKey`）。
pub const UA_KEY: [u8; 3] = [0, 1, 14];

/// 默认固定参数 options（对齐 Dart `ABogus.options`）。
pub const DEFAULT_OPTIONS: [u32; 3] = [0, 1, 14];

/// a_bogus 随机前缀的字节序列长度（Dart `generateRandomBytes(length: 3)` * 4）。
pub const RANDOM_PREFIX_LEN: usize = 12;
