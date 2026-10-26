import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/search/douyin/douyin_search_controller.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';

class DouyinSearchView extends StatelessWidget {
  const DouyinSearchView({super.key});
  DouyinSearchController get controller => Get.find<DouyinSearchController>();

  @override
  Widget build(BuildContext context) {
    // 原本这里拷了两份「width ~/ 200 / width ~/ 500」列数公式，但抖音搜索页
    // 用的是单列列表，两个变量从未被用到——去重时直接删除，不再留第三份拷贝。
    return KeepAliveWrapper(
      child: Stack(
        children: [
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Center(
              child: Padding(
                padding: AppStyle.edgeInsetsA12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      "暂不支持抖音搜索，请打开浏览器搜索，然后复制直播间链接进行解析",
                      textAlign: TextAlign.center,
                    ),
                    TextButton.icon(
                      onPressed: controller.openBrowser,
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text("打开浏览器"),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (Platform.isAndroid || Platform.isIOS)
            InAppWebView(
              onWebViewCreated: controller.onWebViewCreated,
              onLoadStop: controller.onLoadStop,
              onLoadStart: controller.onLoadStart,
              initialSettings: InAppWebViewSettings(
                useOnLoadResource: true,
                userAgent:
                    "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/118.0.0.0",
                useShouldOverrideUrlLoading: true,
              ),
              onCreateWindow: controller.onCreateWindow,
              shouldOverrideUrlLoading: (webController, navigationAction) async {
                var uri = navigationAction.request.url;
                if (uri == null) {
                  return NavigationActionPolicy.ALLOW;
                }
                if (uri.host == "live.douyin.com") {
                  var regExp = RegExp(r"live\.douyin\.com/([\d|\w]+)");
                  var id = regExp.firstMatch(uri.toString())?.group(1) ?? "";

                  AppNavigator.toLiveRoomDetail(site: controller.site, roomId: id);
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
            ),
          Obx(
            () => Visibility(
              visible: controller.pageLoadding.value,
              child: const AppLoaddingWidget(),
            ),
          ),
        ],
      ),
    );
  }
}
