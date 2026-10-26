import 'dart:io';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils/permission_handler.dart';
import 'package:simple_live_app/requests/common_request.dart';
import 'package:url_launcher/url_launcher_string.dart';

typedef TextValidate = bool Function(String text);

class Utils {
  static late PackageInfo packageInfo;
  static DateFormat dateFormat = DateFormat("MM-dd HH:mm");
  static DateFormat dateFormatWithYear = DateFormat("yyyy-MM-dd HH:mm");
  static DateFormat timeFormat = DateFormat("HH:mm:ss");

  /// 处理时间
  static String parseTime(DateTime? dt) {
    if (dt == null) {
      return "";
    }

    var dtNow = DateTime.now();
    if (dt.year == dtNow.year && dt.month == dtNow.month && dt.day == dtNow.day) {
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }

    if (dt.year == dtNow.year) {
      return dateFormat.format(dt);
    }

    return dateFormatWithYear.format(dt);
  }

  /// 提示弹窗
  /// - `content` 内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容，留空为确定
  /// - `cancel` 取消按钮内容，留空为取消
  static Future<bool> showAlertDialog(
    String content, {
    String title = '',
    String confirm = '',
    String cancel = '',
    bool selectable = false,
    List<Widget>? actions,
  }) async {
    var result = await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Container(
          constraints: const BoxConstraints(
            maxHeight: 400,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: AppStyle.edgeInsetsV12,
              child: selectable ? SelectableText(content) : Text(content),
            ),
          ),
        ),
        actions: [
          ...?actions,
          TextButton(
            onPressed: (() => Get.back(result: false)),
            child: Text(cancel.isEmpty ? "取消" : cancel),
          ),
          TextButton(
            onPressed: (() => Get.back(result: true)),
            child: Text(confirm.isEmpty ? "确定" : confirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 提示弹窗
  /// - `content` 内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容，留空为确定
  static Future<bool> showMessageDialog(String content,
      {String title = '', String confirm = '', bool selectable = false}) async {
    var result = await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Padding(
          padding: AppStyle.edgeInsetsV12,
          child: selectable ? SelectableText(content) : Text(content),
        ),
        actions: [
          TextButton(
            onPressed: (() => Get.back(result: true)),
            child: Text(confirm.isEmpty ? "确定" : confirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static void showRightDialog({
    required String title,
    Function()? onDismiss,
    required Widget child,
    double width = 320,
    bool useSystem = false,
  }) {
    SmartDialog.show(
      alignment: Alignment.topRight,
      // keepSingle：这块面板在语义上**只有一个**（`hideRightDialog` 收的就是
      // allCustom 全部），但没设 keepSingle 之前每次调用都往队列里追加一份，
      // 于是连点同一个入口（快捷键、或鼠标狂点条带上的清晰度/换台）会把面板
      // 一层层叠起来。设了之后重复调用改成**原地换内容**：已经开着「清晰度」
      // 时再按「换台」，是同一块面板换成换台列表，而不是盖第二块。
      // continueKeepSingle 让这种原地替换不再重放滑入动画——否则狂点时面板
      // 会反复抽动。
      keepSingle: useSystem ? null : true,
      nonAnimationTypes: const [
        SmartNonAnimationType.routeClose_nonAnimation,
        SmartNonAnimationType.continueKeepSingle,
      ],
      animationBuilder: (controller, child, animationParam) {
        //从右到左
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(controller.view),
          child: child,
        );
      },
      useSystem: useSystem,
      maskColor: Colors.transparent,
      animationTime: const Duration(milliseconds: 200),
      builder: (context) => Material(
        // 用本地 context 取主题：Get.theme 不建立 InheritedWidget 依赖，
        // 面板在主题切换后不会重建，会一直用旧底色。
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width + MediaQuery.of(context).padding.right,
          child: Padding(
            padding: EdgeInsets.only(
              right: MediaQuery.of(context).padding.right,
            ),
            child: SafeArea(
              left: false,
              right: false,
              child: MediaQuery(
                data: const MediaQueryData(padding: EdgeInsets.zero),
                child: Column(
                  children: [
                    ListTile(
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      leading: IconButton(
                        tooltip: "返回",
                        onPressed: () {
                          SmartDialog.dismiss(status: SmartStatus.allCustom)
                              .then(
                            (value) => onDismiss?.call(),
                          );
                        },
                        icon: const Icon(Icons.arrow_back),
                      ),
                      title: Text(
                        title,
                        style: context.textTheme.titleMedium,
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Colors.grey.withAlpha(25),
                    ),
                    Expanded(
                      child: child,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void hideRightDialog() {
    SmartDialog.dismiss(status: SmartStatus.allCustom);
  }

  static Future showBottomSheet({
    required String title,
    required Widget child,
    double maxWidth = 600,
  }) async {
    var result = await showModalBottomSheet(
      context: Get.context!,
      constraints: BoxConstraints(
        maxWidth: maxWidth,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      builder: (_) => Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.only(
              left: 12,
            ),
            title: Text(title),
            trailing: IconButton(
              tooltip: "关闭",
              onPressed: Get.back,
              icon: const Icon(Remix.close_line),
            ),
          ),
          Expanded(
            child: child,
          ),
        ],
      ),
    );
    return result;
  }

  /// 文本编辑的弹窗
  /// - `content` 编辑框默认的内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容
  /// - `cancel` 取消按钮内容
  static Future<String?> showEditTextDialog(
    String content, {
    String title = '',
    String? hintText,
    String confirm = '',
    String cancel = '',
    TextValidate? validate,
  }) async {
    final TextEditingController textEditingController = TextEditingController(text: content);
    var result = await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Padding(
          padding: AppStyle.edgeInsetsT12,
          child: TextField(
            controller: textEditingController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              //prefixText: title,
              contentPadding: AppStyle.edgeInsetsA12,
              hintText: hintText ?? title,
            ),
            // style: TextStyle(
            //     height: 1.0,
            //     color: Get.isDarkMode ? Colors.white : Colors.black),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              if (validate != null && !validate(textEditingController.text)) {
                return;
              }

              Get.back(result: textEditingController.text);
            },
            child: const Text("确定"),
          ),
        ],
      ),
      // barrierColor:
      //     Get.isDarkMode ? Colors.grey.withOpacity(.3) : Colors.black38,
    );
    return result;
  }

  /// 多行文本编辑的弹窗
  /// - `items` 文本项配置
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容
  /// - `cancel` 取消按钮内容
  static Future<Map<String, String>?> showEditTextsDialog(
    List<TextEditItem> items, {
    String title = '',
    String confirm = '',
    String cancel = '',
  }) async {
    final controllers = items.map((item) => TextEditingController(text: item.value)).toList();
    final result = await Get.dialog<Map<String, String>>(
      AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                TextField(
                  controller: controllers[i],
                  autofocus: i == 0,
                  obscureText: items[i].obscureText,
                  keyboardType: items[i].keyboardType,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding: AppStyle.edgeInsetsA12,
                    labelText: items[i].label,
                    hintText: items[i].hintText,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              cancel.isEmpty ? '取消' : cancel,
            ),
          ),
          TextButton(
            onPressed: () {
              for (int i = 0; i < items.length; i++) {
                final validate = items[i].validate;
                if (validate != null && !validate(controllers[i].text)) {
                  return;
                }
              }
              Get.back(
                result: {
                  for (int i = 0; i < items.length; i++) items[i].key: controllers[i].text,
                },
              );
            },
            child: Text(
              confirm.isEmpty ? '确定' : confirm,
            ),
          ),
        ],
      ),
    );
    for (final controller in controllers) {
      controller.dispose();
    }
    return result;
  }

  static Future<T?> showOptionDialog<T>(
    List<T> contents,
    T value, {
    String title = '',
  }) async {
    var result = await Get.dialog(
      SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: value,
            onChanged: (e) {
              Get.back(result: e);
            },
            child: Column(
              children: contents
                  .map(
                    (e) => RadioListTile<T>(
                      title: Text(e.toString()),
                      value: e,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
    return result;
  }

  static Future<T?> showInformationHelpDialog<T>({
    required List<Widget> content,
    Widget? title,
    List<Widget>? actions,
  }) async {
    var result = await Get.dialog(
      AlertDialog(
        title: title ?? const Text("帮助"),
        scrollable: true,
        content: SingleChildScrollView(child: ListBody(children: content)),
        actions: actions ??
            [
              TextButton(
                onPressed: Get.back,
                child: const Text("确定"),
              ),
            ],
      ),
    );
    return result;
  }

  /// 桌面端「返回」：优先关闭 SmartDialog 弹窗，否则收起当前页。
  ///
  /// 原先这份逻辑长在 `main.dart` 的 `MyApp.appBack`，现在搬到这里、`MyApp` 改成
  /// 委托一行。搬的原因是直播间快捷键挂件也要用它（「退出/关闭播放器」的最后一级），
  /// 而它绝不能 import `main.dart`：`main → app_pages → live_room_page → 挂件`
  /// 已经是一条 import 链，反向再指回去就是循环。
  ///
  /// SmartDialog 的 useSystem 弹窗由 Navigator 路由承载，若被 `Get.back()` 直接
  /// 弹出，后续 dismiss 会再次 pop 导致 Navigator 状态异常——所以弹窗必须先自己关。
  static void appBack() {
    if (SmartDialog.checkExist()) {
      SmartDialog.dismiss(status: SmartStatus.smart);
      return;
    }
    // 用 maybePop 而不是 back：PopScope 只对 maybePop 生效，裸 pop 会绕过它。
    // 直播间页多开时靠 PopScope 拦下第一下返回（只收起其余几路），用 back 会
    // 直接把整页弹掉、四路一起销毁。
    Get.key.currentState?.maybePop();
  }

  static Future showStatement() async {
    var text = await rootBundle.loadString("assets/statement.txt");

    var result = await showAlertDialog(
      text,
      selectable: true,
      title: "免责声明",
      confirm: "已阅读并同意",
      cancel: "退出",
    );
    if (!result) {
      exit(0);
    }
  }

  static Future<T?> showMapOptionDialog<T>(
    Map<T, String> contents,
    T value, {
    String title = '',
  }) async {
    var result = await Get.dialog(
      SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: value,
            onChanged: (e) {
              Get.back(result: e);
            },
            child: Column(
              children: contents.keys
                  .map(
                    (e) => RadioListTile<T>(
                      title: Text((contents[e] ?? '-').tr),
                      value: e,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
    return result;
  }

  static void checkUpdate({bool showMsg = false}) async {
    try {
      int currentVer = Utils.parseVersion(packageInfo.version);
      CommonRequest request = CommonRequest();
      var versionInfo = await request.checkUpdate();
      if (versionInfo.versionNum > currentVer) {
        Get.dialog(
          AlertDialog(
            title: Text(
              "发现新版本 ${versionInfo.version}",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            content: Text(
              versionInfo.versionDesc,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            actionsPadding: AppStyle.edgeInsetsH12,
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Get.back();
                      },
                      child: const Text("取消"),
                    ),
                  ),
                  AppStyle.hGap12,
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                      ),
                      onPressed: () {
                        launchUrlString(
                          versionInfo.downloadUrl,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      child: const Text("更新"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      } else {
        if (showMsg) {
          SmartDialog.showToast("当前已经是最新版本了");
        }
      }
    } catch (e) {
      Log.logPrint(e);
      if (showMsg) {
        SmartDialog.showToast("检查更新失败");
      }
    }
  }

  static int parseVersion(String version) {
    var sp = version.split('.');
    var num = "";
    for (var item in sp) {
      num = num + item.padLeft(2, '0');
    }
    return int.parse(num);
  }

  static String onlineToString(int num) {
    if (num >= 10000) {
      return "${(num / 10000.0).toStringAsFixed(1)}万";
    }
    return num.toString();
  }

  /// 检查相册权限
  static Future<bool> checkPhotoPermission() async {
    try {
      if (!Platform.isIOS) {
        return true;
      }
      var status = await Permission.photos.status;
      if (status == PermissionStatus.granted) {
        return true;
      }
      status = await Permission.photos.request();
      if (status.isGranted) {
        return true;
      } else {
        SmartDialog.showToast(
          "请授予相册访问权限",
        );
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  /// 检查文件权限
  static Future<bool> checkStorgePermission() async {
    try {
      if (!Platform.isAndroid) {
        return true;
      }
      Permission permission = Permission.storage;
      var androidIndo = await deviceInfo.androidInfo;
      if (androidIndo.version.sdkInt >= 33) {
        permission = Permission.manageExternalStorage;
      }

      var status = await permission.status;
      if (status == PermissionStatus.granted) {
        return true;
      }
      status = await permission.request();
      if (status.isGranted) {
        return true;
      } else {
        SmartDialog.showToast(
          "请授予文件访问权限",
        );
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  ///16进制颜色转换
  static Color convertHexColor(String hexColor) {
    hexColor = hexColor.replaceAll("#", "");
    if (hexColor.length == 4) {
      hexColor = "00$hexColor";
    }

    if (hexColor.length == 6) {
      var R = int.parse(hexColor.substring(0, 2), radix: 16);
      var G = int.parse(hexColor.substring(2, 4), radix: 16);
      var B = int.parse(hexColor.substring(4, 6), radix: 16);
      return Color.fromARGB(255, R, G, B);
    }
    if (hexColor.length == 8) {
      var A = int.parse(hexColor.substring(0, 2), radix: 16);
      var R = int.parse(hexColor.substring(2, 4), radix: 16);
      var G = int.parse(hexColor.substring(4, 6), radix: 16);
      var B = int.parse(hexColor.substring(6, 8), radix: 16);

      return Color.fromARGB(A, R, G, B);
    }

    return Colors.white;
  }

  /// 复制内容到剪贴板
  static void copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      SmartDialog.showToast("已复制到剪贴板");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("复制到剪贴板失败: $e");
    }
  }

  /// 获取剪贴板内容
  static Future<String?> getClipboard() async {
    try {
      var content = await Clipboard.getData(Clipboard.kTextPlain);
      if (content == null) {
        SmartDialog.showToast("无法读取剪贴板内容");
        return null;
      }
      return content.text;
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("读取剪切板内容失败：$e");
    }
    return null;
  }

  static bool isRegexFormat(String keyword) {
    return keyword.startsWith('/') && keyword.endsWith('/') && keyword.length > 2;
  }

  static String removeRegexFormat(String keyword) {
    return keyword.substring(1, keyword.length - 1);
  }

  static String parseFileSize(int size) {
    if (size < 1024) {
      return "$size B";
    }
    if (size < 1024 * 1024) {
      return "${(size / 1024).toStringAsFixed(2)} KB";
    }
    if (size < 1024 * 1024 * 1024) {
      return "${(size / 1024 / 1024).toStringAsFixed(2)} MB";
    }
    return "${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB";
  }

  /// 随屏幕缩放比例调整
  static double scaleValue({
    required double value,
    required double playerH,
    required double designH,
    double upSens = 0.8,
    double downSens = 0.5,
    required double minSize,
    required double maxSize,
  }) {
    if (designH <= 0 || minSize >= maxSize) {
      return value;
    }
    // 限制
    double safeUpSens = upSens.clamp(0.0, 1.5);
    double safeDownSens = downSens.clamp(0.0, 1.0);
    var ratio = playerH / designH;
    // 双向控制放缩比率
    var adjustedRatio = ratio > 1 ? math.pow(ratio, safeUpSens).toDouble() : 1 - (1 - ratio) * safeDownSens;

    var result = value * adjustedRatio;
    var clamped = result.clamp(minSize, maxSize);
    return clamped.roundToDouble();
  }
}

class TextEditItem {
  final String key;
  final String value;
  final String? label;
  final String? hintText;
  final TextValidate? validate;
  final bool obscureText;
  final TextInputType? keyboardType;

  const TextEditItem({
    required this.key,
    this.value = '',
    this.label,
    this.hintText,
    this.validate,
    this.obscureText = false,
    this.keyboardType,
  });
}
