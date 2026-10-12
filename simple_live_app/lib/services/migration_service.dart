import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/extensions/duration_2_str_utils.dart';
import 'package:simple_live_app/models/db/account.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

class MigrationService {
  /// 将Hive数据迁移到Application Support
  static Future migrateData() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return;
    }
    var hiveFileList = [
      "followuser",
      //旧版本写错成hostiry了
      "hostiry",
      "followusertag",
      "localstorage",
      "danmushield",
    ];
    try {
      var newDir = await getApplicationSupportDirectory();
      var hiveFile = File(p.join(newDir.path, "followuser.hive"));
      if (await hiveFile.exists()) {
        return;
      }

      var oldDir = await getApplicationDocumentsDirectory();
      for (var element in hiveFileList) {
        var oldFile = File(p.join(oldDir.path, "$element.hive"));
        if (await oldFile.exists()) {
          var fileName = "$element.hive";
          if (element == "hostiry") {
            fileName = "history.hive";
          }
          await oldFile.copy(p.join(newDir.path, fileName));
          await oldFile.delete();
        }
        var lockFile = File(p.join(oldDir.path, "$element.lock"));
        if (await lockFile.exists()) {
          await lockFile.delete();
        }
      }
    } catch (e) {
      Log.logPrint(e);
    }
  }

  /// 数据迁移根据版本：from 1.7.8
  static Future<void> migrateDataByVersion() async {
    int curAppVer = Utils.parseVersion(Utils.packageInfo.version);
    int curDBVer = LocalStorageService.instance.getValue(LocalStorageService.kHiveDbVer, 10708);
    Log.i("curDBVer: $curDBVer, curAppVer: $curAppVer");
    if (curDBVer <= 10708) {
      LocalStorageService.instance.settingsBox.delete(LocalStorageService.kWebDAVLastUploadTime);
      LocalStorageService.instance.settingsBox.delete(LocalStorageService.kWebDAVLastRecoverTime);
    }
    // follow_user 添加 tag属性
    // 从followUserTag 读取 标签
    if (curDBVer <= 10709) {
      List tagList = DBService.instance.tagBox.values.toList();
      List<FollowUser> followList = DBService.instance.followBox.values.toList();
      for (int i = 0; i < followList.length; i++) {
        for (FollowUserTag tag in tagList) {
          if (tag.userId.contains(followList[i].id)) {
            followList[i].tag = tag.tag;
            DBService.instance.addFollow(followList[i]);
            break;
          }
        }
      }
    }
    // sortkey-romanName
    if (curDBVer <= 10805) {
      await FollowService.instance.followUserAllDataCheck();
    }

    // migrate follow.watchDuration -> follow.watchDurationSec
    // easy to calculate
    // delete this attribute after v10810, I think
    // hive logic temp:
    // old: watchDuration: fields[6] == null ? "00:00:00" : fields[6] as String?
    // new: otherAtr(any type): fields[6] == null ? anyTypeValue : fields[6] as String to anyType
    // String to int: like watchDurationSec, String.toDuration.toInt
    if (curDBVer <= 10807) {
      var followList = DBService.instance.followBox.values.toList();
      for (FollowUser follow in followList) {
        follow.watchDurationSec = follow.watchDuration!.toDuration().inSeconds;
        DBService.instance.addFollow(follow);
      }
    }
    // set follow.lastWatchTime as cur timestamp after v10810
    if (curDBVer <= 10809) {
      var followList = DBService.instance.followBox.values.toList();
      var now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (FollowUser follow in followList) {
        if (follow.lastWatchTime == 0) {
          follow.lastWatchTime = now;
          DBService.instance.addFollow(follow);
        }
      }
      Log.i("Migration: initialized lastWatchTime for ${followList.length} follows");
    }

    // form local-storage cookie -> Accounts after v10815
    if (curDBVer <= 10815) {
      var curTime = DateTime.now().millisecondsSinceEpoch;
      var accountList = DBService.instance.getAllAccounts();
      var existingSiteIds = accountList.map((e) => e.siteId).toSet();
      // migration from map<String, cookie> to AccountModel
      var biliCredential = jsonEncode({
        'cookie': LocalStorageService.instance.getValue(LocalStorageService.kBilibiliCookie, ''),
      });
      var douyuCredential = jsonEncode({
        'cookie': LocalStorageService.instance.getValue(LocalStorageService.kDouyuCookie, ''),
        'dy_did': LocalStorageService.instance.getValue(LocalStorageService.kDouyuDyDid, ''),
        'LTP0': LocalStorageService.instance.getValue(LocalStorageService.kDouyuLTP0, ''),
      });

      var douyinCredential = jsonEncode({
        'cookie': LocalStorageService.instance.getValue(LocalStorageService.kDouyinCookie, ''),
      });

      final defaults = [
        Account(
          id: '0',
          siteId: Constant.kBiliBili,
          credential: biliCredential,
          isActive: false,
          supportCookieLogin: true,
          supportQRLogin: true,
          supportWebLogin: true,
          createdAt: curTime,
          updatedAt: curTime,
        ),
        Account(
            id: '1',
            siteId: Constant.kDouyu,
            credential: douyuCredential,
            isActive: false,
            supportCookieLogin: true,
            supportQRLogin: true,
            createdAt: curTime,
            updatedAt: curTime),
        Account(
          id: '2',
          siteId: Constant.kDouyin,
          credential: douyinCredential,
          isActive: false,
          supportCookieLogin: true,
          createdAt: curTime,
          updatedAt: curTime,
        ),
      ];

      for (final ac in defaults) {
        if (existingSiteIds.contains(ac.siteId) == false) {
          DBService.instance.addAccount(ac);
        }
      }
    }

    // follow.tag -> followUserTag.userId 归属真源迁移（v1.8.16）
    if (curDBVer <= 10816) {
      await migrateTagMembership();
      // FollowService 已在 main.dart 里先于本方法 put，内存态的 followTagList
      // 是迁移前从 tagBox 读的旧副本，必须重载，否则关注页看不到补上的成员。
      FollowService.instance.getAllTagList();
    }

    LocalStorageService.instance.settingsBox.put(LocalStorageService.kHiveDbVer, curAppVer);
  }

  /// 归属真源迁移：把 `FollowUser.tag` 单向灌进 `FollowUserTag.userId`。
  ///
  /// 多分组归属之后 `userId` 是唯一真源，`FollowUser.tag` 降级为「主分组」展示缓存，
  /// 最终在后续版本删除。这里只做**补全**：
  /// - `tag == '全部'`（哨兵）的关注不进任何分组；
  /// - `tag` 指向的分组不存在时新建（孤儿名字，原来靠 `followUserAllDataCheck` 修）；
  /// - 已在 `userId` 里的跳过，重复执行无副作用。
  static Future<void> migrateTagMembership() async {
    final followList = DBService.instance.getFollowList();
    final tagList = DBService.instance.getFollowTagList();
    final byName = {for (final t in tagList) t.tag: t};

    for (final follow in followList) {
      if (follow.tag == '全部' || follow.tag.isEmpty) {
        continue;
      }
      var tag = byName[follow.tag];
      if (tag == null) {
        tag = await DBService.instance.addFollowTag(follow.tag);
        byName[follow.tag] = tag;
      }
      if (!tag.userId.contains(follow.id)) {
        tag.userId.add(follow.id);
        await DBService.instance.updateFollowTag(tag);
      }
    }
    Log.i("Migration: tag -> userId membership backfilled "
        "(${followList.length} follows, ${byName.length} tags)");
  }
}
