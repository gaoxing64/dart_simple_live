/// 增量 FLV 解析：喂入任意大小的字节块，按需吐出完整 tag。
///
/// 这是「续流中转」（[StreamRelayService]）的纯逻辑部分：把一条 FLV 流
/// 解析成 tag 序列，用于记录已转发的时间轴位置、以及在旧流断开后从新流
/// 的第一个合适关键帧处接续。不涉及任何 IO，可直接单测。
///
/// 接续之所以成立，是因为斗鱼 flv tag 用的是推流会话的**绝对时间戳**：
/// 重新取流后时间轴延续而非归零，所以不需要改写时间戳，只要丢掉新流的
/// 文件头与初始化 tag，并从第一个未落后于已转发位置的关键帧接上即可。
library;

import 'dart:typed_data';

/// FLV tag 类型：音频。
const int kFlvTagTypeAudio = 8;

/// FLV tag 类型：视频。
const int kFlvTagTypeVideo = 9;

/// FLV tag 类型：脚本（onMetaData 等元数据）。
const int kFlvTagTypeScript = 18;

/// 解析缓冲的上限。单个 FLV tag 远小于此值，超过即说明字节流无法按 FLV 解析。
const int kFlvMaxPendingBuffer = 8 * 1024 * 1024;

final Uint8List _emptyBytes = Uint8List(0);

/// 一个完整的 FLV tag：11 字节 tag 头 + data + 4 字节 PreviousTagSize。
class FlvTag {
  /// 完整 tag 字节（`nextTag(keepRaw: false)` 时为空）。
  final Uint8List raw;

  /// tag 类型（8 音频 / 9 视频 / 18 脚本）。
  final int tagType;

  /// 时间戳（毫秒）。高 8 位来自 tag 头的 TimestampExtended 字节。
  final int timestamp;

  /// 视频关键帧（FrameType == 1）。
  final bool isKeyframe;

  /// 初始化 tag（视频/音频的 sequence header），播放器只需首段的那一份。
  final bool isSequenceHeader;

  FlvTag({
    required this.raw,
    required this.tagType,
    required this.timestamp,
    required this.isKeyframe,
    required this.isSequenceHeader,
  });
}

class FlvDemuxer {
  Uint8List _buf = _emptyBytes;
  int _start = 0;
  Uint8List? _header;
  bool _headerParsed = false;

  int get _length => _buf.length - _start;

  /// 喂入任意大小的字节块。
  void push(List<int> chunk) {
    final remain = _length;
    final next = Uint8List(remain + chunk.length);
    if (remain > 0) {
      next.setRange(0, remain, _buf, _start);
    }
    next.setRange(remain, remain + chunk.length, chunk);
    _buf = next;
    _start = 0;
  }

  Uint8List _take(int n) {
    final out = _buf.sublist(_start, _start + n);
    _start += n;
    return out;
  }

  /// 解析文件头（"FLV" + 版本 + 标志 + dataOffset，后随 PreviousTagSize0）。
  /// 返回 false 表示数据还不够，下次再试。
  bool _tryParseHeader() {
    if (_headerParsed) {
      return true;
    }
    if (_length < 13) {
      return false;
    }
    if (_buf[_start] == 0x46 && _buf[_start + 1] == 0x4C && _buf[_start + 2] == 0x56) {
      final dataOffset = (_buf[_start + 5] << 24) |
          (_buf[_start + 6] << 16) |
          (_buf[_start + 7] << 8) |
          _buf[_start + 8];
      final total = dataOffset + 4;
      if (_length < total) {
        return false;
      }
      _header = _take(total);
    }
    _headerParsed = true;
    return true;
  }

  /// 必须自行触发解析：调用方会先取文件头再取 tag，
  /// 若等到 [nextTag] 才解析，文件头就会排到首批 tag 之后发出。
  Uint8List? takeHeader() {
    _tryParseHeader();
    final header = _header;
    _header = null;
    return header;
  }

  /// 缓冲越积越多却吐不出 tag，说明上游不是能按 FLV 解析的字节流。
  /// 用于兜底，避免在非预期容器上无限占用内存。
  bool get isDesynced => _length > kFlvMaxPendingBuffer;

  void reset() {
    _buf = _emptyBytes;
    _start = 0;
    _header = null;
    _headerParsed = false;
  }

  /// 取出下一个完整的 tag；数据不够返回 null。
  ///
  /// [keepRaw] 为 false 时只解析元信息、不复制字节（首段只需要记录时间轴，
  /// 原始字节已经原样转发给播放器，没必要再复制一份）。
  FlvTag? nextTag({bool keepRaw = true}) {
    if (!_tryParseHeader()) {
      return null;
    }
    if (_length < 11) {
      return null;
    }
    final dataSize = (_buf[_start + 1] << 16) | (_buf[_start + 2] << 8) | _buf[_start + 3];
    final total = 11 + dataSize + 4;
    if (_length < total) {
      return null;
    }

    final tagType = _buf[_start] & 0x1f;
    // 时间戳 = 3 字节大端（偏移 4..6）+ 1 字节高位扩展（偏移 7）。
    final timestamp = (_buf[_start + 4] << 16) |
        (_buf[_start + 5] << 8) |
        _buf[_start + 6] |
        (_buf[_start + 7] << 24);

    var isKeyframe = false;
    var isSequenceHeader = false;
    if (dataSize >= 2) {
      final first = _buf[_start + 11];
      final second = _buf[_start + 12];
      // 视频：高 4 位为帧类型（1 = 关键帧），后一字节为 0 表示 sequence header。
      // 音频：后一字节为 0 表示 AAC sequence header。
      if (tagType == kFlvTagTypeVideo) {
        isKeyframe = (first >> 4) == 1;
        isSequenceHeader = second == 0;
      } else if (tagType == kFlvTagTypeAudio) {
        isSequenceHeader = second == 0;
      }
    }

    final Uint8List raw;
    if (keepRaw) {
      raw = _take(total);
    } else {
      _start += total;
      raw = _emptyBytes;
    }

    return FlvTag(
      raw: raw,
      tagType: tagType,
      timestamp: timestamp,
      isKeyframe: isKeyframe,
      isSequenceHeader: isSequenceHeader,
    );
  }
}

/// 记录已转发到的时间轴位置，用于在接续时丢弃新流回吐的重复 tag。
/// 音视频分开记录，避免交错导致误丢。
class FlvTimeline {
  int? _lastVideoTs;
  int? _lastAudioTs;

  void observe(FlvTag tag) {
    if (tag.tagType == kFlvTagTypeVideo) {
      _lastVideoTs = tag.timestamp;
    } else if (tag.tagType == kFlvTagTypeAudio) {
      _lastAudioTs = tag.timestamp;
    }
  }

  /// 新流的 tag 是否没有落后于旧流转发到的位置（时间戳**相等也算**）。
  ///
  /// 用「相等也算」而不是严格大于：实测真实斗鱼流里存在约 1/s 的「与前一帧
  /// 同毫秒」的音频 tag（时间戳完全相等）。接续段若按严格大于过滤，会把这些
  /// 真实帧当成「CDN 回吐的重复内容」整段丢掉，形成周期性音频丢帧。
  ///
  /// 被拦的是「回吐」——重复内容的时间戳落后旧位置若干毫秒到一整个 GOP；
  /// 换成 `>=` 后最坏只在接续边界多转发一帧与已发帧同毫秒的重复帧，
  /// 对播放器无感。
  bool isNotBehind(FlvTag tag) {
    final last = switch (tag.tagType) {
      kFlvTagTypeVideo => _lastVideoTs,
      kFlvTagTypeAudio => _lastAudioTs,
      _ => null,
    };
    if (last == null) {
      return true;
    }
    return tag.timestamp >= last;
  }
}
