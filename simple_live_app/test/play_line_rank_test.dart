// 线路优选（core `play::rank*`）的运行时契约测试。
//
// 为什么在这里而不是 core 包：core 是纯 Dart 包，没有 flutter_test；而这段代码
// 的价值恰恰是验证 **Dart ↔ Rust 的绑定契约**（枚举映射、BigInt 下标、sync 调用），
// 只有真正加载编译产物才能证明。
//
// 依赖构建产物：未构建时整组跳过（CI 上不装 Rust 工具链也能过）。

import 'dart:io';

// ExternalLibrary 未从 flutter_rust_bridge 公共面导出；测试里需要显式指定
// 构建产物路径，故直接引内部实现（仅测试文件，生产代码不走这条路）。
// ignore: implementation_imports
// ignore: depend_on_referenced_packages
import 'package:flutter_rust_bridge/src/platform_types/_io.dart' show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 构建产物路径（相对包根，`flutter test` 的 cwd 即包根）。
String? _libraryPath() {
  if (!Platform.isWindows) {
    return null;
  }
  final file = File('build/windows/x64/runner/Debug/rust_lib_simple_live_app.dll');
  return file.existsSync() ? file.absolute.path : null;
}

void main() {
  final libraryPath = _libraryPath();
  final skipReason = libraryPath == null ? "未找到构建产物，跳过（先 flutter build windows）" : null;

  setUpAll(() async {
    if (libraryPath == null) {
      return;
    }
    await RustLib.init(externalLibrary: ExternalLibrary.open(libraryPath));
  });

  test("静态优选：flv 在前，mcdn 降级但不丢弃", () {
    final lines = PlayLineRanker.rank(
      platformId: "bilibili",
      urls: [
        "https://cn-hbxy-cu-01-11.mcdn.bilivideo.cn:4483/playurl?cdn=mcdn",
        "https://d1--cn-gotcha04.bilivideo.com/live/a.flv?cdn=cn-gotcha04",
      ],
    );

    expect(lines, hasLength(2), reason: "降级不等于丢弃");
    expect(lines.first.host, "d1--cn-gotcha04.bilivideo.com");
    expect(lines.first.kind, LiveLineKind.flv);
    expect(lines.last.hint, LiveLineHint.mcdn);
    expect(lines.last.originIndex, 0, reason: "原始下标要能回指");
  }, skip: skipReason);

  test("静态优选：同容器内保持平台原序（稳定排序）", () {
    final lines = PlayLineRanker.rank(
      platformId: "huya",
      urls: [
        "http://a.flv.huya.com/src/1.flv",
        "http://b.flv.huya.com/src/2.flv",
        "http://c.hls.huya.com/src/3.m3u8",
      ],
    );

    expect(lines.map((e) => e.host).toList(), [
      "a.flv.huya.com",
      "b.flv.huya.com",
      "c.hls.huya.com",
    ]);
  }, skip: skipReason);

  test("HLS 优先：preferHls 翻转容器顺序", () {
    final lines = PlayLineRanker.rank(
      platformId: "douyin",
      urls: [
        "http://pull-x3-t5.douyincdn.com/a.flv",
        "http://pull-x3-t5-hls.douyincdn.com/b.m3u8",
      ],
      preferHls: true,
    );

    expect(lines.first.kind, LiveLineKind.hls);
  }, skip: skipReason);

  test("续流重排：按主机序还原，保证下标仍指向同一条 CDN", () {
    final reordered = PlayLineRanker.reorder(
      urls: [
        "http://al.hls.huya.com/src/9.m3u8?wsSecret=NEW",
        "http://tx.flv.huya.com/src/9.flv?wsSecret=NEW",
      ],
      hostOrder: ["tx.flv.huya.com", "al.hls.huya.com"],
    );

    expect(reordered.first, contains("tx.flv.huya.com"));
    expect(reordered.last, contains("al.hls.huya.com"));
  }, skip: skipReason);

  test("续流重排：同一 CDN 的多条线路不会被折叠", () {
    // 虎牙真实形态：一个主机下发多条 stream。主机序里有重复项时，
    // 必须按「槽位消费」一一对应，否则第 2 条线路会被换成另一条 CDN。
    final urls = [
      "http://al.flv.huya.com/a.flv",
      "http://tx.flv.huya.com/b.flv",
      "http://al.flv.huya.com/c.flv",
    ];
    expect(
      PlayLineRanker.reorder(
        urls: urls,
        hostOrder: ["al.flv.huya.com", "tx.flv.huya.com", "al.flv.huya.com"],
      ),
      urls,
      reason: "原序主机序重排后应完全不变",
    );
  }, skip: skipReason);

  test("续流重排：空主机序是恒等变换", () {
    final urls = ["http://a/x.flv", "http://b/y.flv"];
    expect(PlayLineRanker.reorder(urls: urls, hostOrder: const []), urls);
  }, skip: skipReason);
}
