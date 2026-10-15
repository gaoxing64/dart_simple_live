import 'dart:convert';

/// 直链到期后重新取流的回调：返回同一线路的一条新直链。
///
/// 部分平台下发的播放直链带硬性寿命（例如斗鱼给第三方的 FLV 直链固定
/// 300 秒后由 CDN 主动断开，与网络、线路、清晰度无关），播放层据此在
/// 到期前自行续流，避免每 5 分钟中断一次。
typedef LivePlayUrlRenewer = Future<String> Function();

class LivePlayUrl {
  /// 播放地址
  final List<String> urls;

  /// 请求头
  final Map<String, String>? headers;

  /// 与 [urls] 一一对应的续流回调：在旧直链到期前调用它拿到新直链。
  ///
  /// 仅在直链带时效、需要在线续流的平台提供（当前只有斗鱼）。元素为 null
  /// 表示该条线路无法续流（例如非 FLV 容器）；整个列表为 null 表示平台
  /// 不需要续流，播放层按原样直接播放。
  final List<LivePlayUrlRenewer?>? renewers;

  LivePlayUrl({
    required this.urls,
    this.headers,
    this.renewers,
  }) : assert(renewers == null || renewers.length == urls.length,
            "renewers 必须与 urls 一一对应");

  @override
  String toString() {
    return json.encode({
      "urls": urls,
      "headers": headers.toString(),
      "renewable": renewers != null,
    });
  }
}
