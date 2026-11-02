import 'package:simple_live_app/app/constant.dart';

/// 「打开官方 App」的深链对：优先拉起客户端，失败回退网页。
class NativeAppLink {
  const NativeAppLink({required this.nativeUrl, required this.webUrl});

  final String nativeUrl;
  final String webUrl;
}

/// 按平台拼装深链。`roomId` 为通用房间号；`danmakuArgs` 为 Rust 契约
/// JSON 解析出的键值（抖音 `room_id`/`web_rid`、虎牙 `sub_sid`）。
/// 未知平台返回 `null`。
NativeAppLink? buildNativeAppLink(
  String platformId,
  String? roomId,
  Map<String, dynamic> danmakuArgs,
) {
  switch (platformId) {
    case Constant.kBiliBili:
      return NativeAppLink(
        nativeUrl: "bilibili://live/$roomId",
        webUrl: "https://live.bilibili.com/$roomId",
      );
    case Constant.kDouyin:
      return NativeAppLink(
        nativeUrl: "snssdk1128://webcast_room?room_id=${danmakuArgs['room_id']}",
        webUrl: "https://live.douyin.com/${danmakuArgs['web_rid']}",
      );
    case Constant.kHuya:
      final subSid = danmakuArgs['sub_sid'];
      return NativeAppLink(
        nativeUrl:
            "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D$subSid%26subid%3D$subSid%26liveuid%3D$subSid%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide",
        webUrl: "https://www.huya.com/$roomId",
      );
    case Constant.kDouyu:
      return NativeAppLink(
        nativeUrl: "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D$roomId",
        webUrl: "https://www.douyu.com/$roomId",
      );
  }
  return null;
}
