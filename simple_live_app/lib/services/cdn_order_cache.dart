import 'dart:convert';

import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

/// 每个平台「上次实测最优的 CDN 主机顺序」。
///
/// 起播路径只用它做**零成本重排**（一次同步 FFI，微秒级）；真正的网络探测在首帧
/// 之后后台跑，结果回写这里。这样「越用越快」和「起播不等探测」同时成立。
///
/// 只按平台维度存（不是按房间）：CDN 快慢是「这台机器到这个边缘节点」的属性，
/// 与房间无关，换台时同样适用。
class CdnOrderCache {
  CdnOrderCache._();

  static const String _key = "CdnHostOrderV1";

  static final Map<String, List<String>> _memory = <String, List<String>>{};
  static bool _loaded = false;

  /// 读出某平台的首选主机顺序；无记录返回空表。
  static List<String> get(String platformId) {
    _ensureLoaded();
    return _memory[platformId] ?? const [];
  }

  /// 写入某平台的首选主机顺序（长度 < 2 视为无意义，直接忽略）。
  static void put(String platformId, List<String> hostOrder) {
    if (hostOrder.length < 2) {
      return;
    }
    _ensureLoaded();
    _memory[platformId] = List<String>.unmodifiable(hostOrder);
    _persist();
  }

  /// 清空（测试 / 排障用）。
  static void clear() {
    _memory.clear();
    _loaded = true;
    _persist();
  }

  static void _ensureLoaded() {
    if (_loaded) {
      return;
    }
    _loaded = true;
    try {
      final raw = LocalStorageService.instance.getValue<String>(_key, "");
      if (raw.isEmpty) {
        return;
      }
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return;
      }
      decoded.forEach((key, value) {
        if (key is String && value is List) {
          final hosts = value.whereType<String>().toList(growable: false);
          if (hosts.isNotEmpty) {
            _memory[key] = hosts;
          }
        }
      });
    } catch (e) {
      // 缓存坏了只影响优选顺序，绝不影响起播：忽略并继续用静态序。
      Log.logPrint(e);
    }
  }

  static void _persist() {
    try {
      LocalStorageService.instance.setValue(_key, json.encode(_memory));
    } catch (e) {
      Log.logPrint(e);
    }
  }
}
