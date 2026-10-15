import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/stream_relay/flv_demuxer.dart';

/// 拼出一个最小 FLV tag：11 字节头 + data + 4 字节 PreviousTagSize。
Uint8List makeTag(int tagType, int timestamp, List<int> data) {
  final out = BytesBuilder();
  out.addByte(tagType);
  final size = data.length;
  out.add([(size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff]);
  out.add([
    (timestamp >> 16) & 0xff,
    (timestamp >> 8) & 0xff,
    timestamp & 0xff,
    (timestamp >> 24) & 0xff,
  ]);
  out.add([0, 0, 0]);
  out.add(data);
  final prev = 11 + size;
  out.add([(prev >> 24) & 0xff, (prev >> 16) & 0xff, (prev >> 8) & 0xff, prev & 0xff]);
  return out.toBytes();
}

Uint8List flvHeader() {
  final out = BytesBuilder();
  out.add([0x46, 0x4C, 0x56, 0x01, 0x05]); // "FLV" + version + flags
  out.add([0, 0, 0, 9]); // dataOffset = 9
  out.add([0, 0, 0, 0]); // PreviousTagSize0
  return out.toBytes();
}

void main() {
  group('FlvDemuxer', () {
    test('解析文件头与 tag（类型/时间戳/关键帧/初始化 tag）', () {
      final demuxer = FlvDemuxer();
      final bytes = BytesBuilder()
        ..add(flvHeader())
        ..add(makeTag(kFlvTagTypeVideo, 30678210, [0x17, 0x01, 0xaa]))
        ..add(makeTag(kFlvTagTypeAudio, 30678211, [0xaf, 0x01, 0xbb]));
      demuxer.push(bytes.toBytes());

      expect(demuxer.takeHeader(), isNotNull);

      final video = demuxer.nextTag()!;
      expect(video.tagType, kFlvTagTypeVideo);
      expect(video.timestamp, 30678210);
      expect(video.isKeyframe, isTrue);
      expect(video.isSequenceHeader, isFalse);
      expect(video.raw.length, 11 + 3 + 4);

      final audio = demuxer.nextTag()!;
      expect(audio.tagType, kFlvTagTypeAudio);
      expect(audio.timestamp, 30678211);
      expect(audio.isSequenceHeader, isFalse);

      expect(demuxer.nextTag(), isNull);
    });

    test('逐字节喂入也不会解析错位', () {
      final full = (BytesBuilder()
            ..add(flvHeader())
            ..add(makeTag(kFlvTagTypeVideo, 1000, [0x17, 0x01, 0x00, 0x01])))
          .toBytes();

      final demuxer = FlvDemuxer();
      for (final byte in full) {
        demuxer.push([byte]);
      }
      expect(demuxer.takeHeader(), isNotNull);
      final tag = demuxer.nextTag()!;
      expect(tag.timestamp, 1000);
      expect(tag.isKeyframe, isTrue);
    });

    test('识别初始化 tag（sequence header）', () {
      final demuxer = FlvDemuxer();
      final bytes = (BytesBuilder()
            ..add(flvHeader())
            ..add(makeTag(kFlvTagTypeVideo, 0, [0x17, 0x00, 0x00]))
            ..add(makeTag(kFlvTagTypeAudio, 0, [0xaf, 0x00])))
          .toBytes();
      demuxer.push(bytes);
      demuxer.takeHeader();

      expect(demuxer.nextTag()!.isSequenceHeader, isTrue);
      expect(demuxer.nextTag()!.isSequenceHeader, isTrue);
    });

    test('非关键帧不误判：0x27 帧类型', () {
      final demuxer = FlvDemuxer();
      demuxer.push((BytesBuilder()
            ..add(flvHeader())
            ..add(makeTag(kFlvTagTypeVideo, 100, [0x27, 0x01, 0x00])))
          .toBytes());
      demuxer.takeHeader();
      final tag = demuxer.nextTag()!;
      expect(tag.isKeyframe, isFalse);
      expect(tag.isSequenceHeader, isFalse);
    });

    test('keepRaw=false 只解析元信息、不复制字节', () {
      final demuxer = FlvDemuxer();
      demuxer.push((BytesBuilder()
            ..add(flvHeader())
            ..add(makeTag(kFlvTagTypeVideo, 100, [0x17, 0x01, 0x00]))
            ..add(makeTag(kFlvTagTypeVideo, 200, [0x27, 0x01, 0x00])))
          .toBytes());
      demuxer.takeHeader();

      expect(demuxer.nextTag(keepRaw: false)!.raw, isEmpty);
      // 仍然能继续解析下一个 tag。
      expect(demuxer.nextTag(keepRaw: false)!.timestamp, 200);
    });

    test('文件头分片到达时不会提前把 tag 排到前面', () {
      final demuxer = FlvDemuxer();
      demuxer.push(flvHeader().sublist(0, 5));
      expect(demuxer.takeHeader(), isNull); // 数据还不够

      demuxer.push(flvHeader().sublist(5));
      demuxer.push(makeTag(kFlvTagTypeVideo, 10, [0x17, 0x01, 0x00]));
      expect(demuxer.takeHeader(), isNotNull);
      expect(demuxer.nextTag()!.timestamp, 10);
    });

    test('无法按 FLV 解析的字节流会被判定为失同步', () {
      final demuxer = FlvDemuxer();
      // 全 0xFF：dataSize 字段最大、永远等不满一个 tag，无法吐出任何 tag。
      final garbage = Uint8List(kFlvMaxPendingBuffer + 1)..fillRange(0, kFlvMaxPendingBuffer + 1, 0xFF);
      demuxer.push(garbage);
      expect(demuxer.takeHeader(), isNull);
      expect(demuxer.nextTag(), isNull);
      expect(demuxer.isDesynced, isTrue);

      demuxer.reset();
      expect(demuxer.isDesynced, isFalse);
    });
  });

  group('FlvTimeline', () {
    test('丢弃新流回吐的旧 GOP（相等时间戳不算落后），音视频时间轴互相独立', () {
      final timeline = FlvTimeline();
      final demuxer = FlvDemuxer();
      final bytes = (BytesBuilder()
            ..add(flvHeader())
            ..add(makeTag(kFlvTagTypeVideo, 500, [0x17, 0x01, 0x00]))
            ..add(makeTag(kFlvTagTypeVideo, 400, [0x17, 0x01, 0x00]))
            ..add(makeTag(kFlvTagTypeVideo, 500, [0x17, 0x01, 0x00]))
            ..add(makeTag(kFlvTagTypeVideo, 600, [0x17, 0x01, 0x00])))
          .toBytes();
      demuxer.push(bytes);
      demuxer.takeHeader();

      final first = demuxer.nextTag()!;
      expect(timeline.isNotBehind(first), isTrue);
      timeline.observe(first);

      // 回吐的旧 GOP 应被丢弃。
      final replayed = demuxer.nextTag()!;
      expect(timeline.isNotBehind(replayed), isFalse);

      // 同毫秒的真实帧不算落后（真实斗鱼流里每秒都有这种音频帧，不能丢）。
      final sameMillisecond = demuxer.nextTag()!;
      expect(sameMillisecond.timestamp, 500);
      expect(timeline.isNotBehind(sameMillisecond), isTrue);

      // 视频已到 500，音频时间轴独立判断：任何音频 tag 都算未落后。
      final audio = FlvTag(
        raw: Uint8List(0),
        tagType: kFlvTagTypeAudio,
        timestamp: 100,
        isKeyframe: false,
        isSequenceHeader: false,
      );
      expect(timeline.isNotBehind(audio), isTrue);
    });

    test('音频用独立时间轴判断', () {
      final timeline = FlvTimeline();
      timeline.observe(FlvTag(
        raw: Uint8List(0),
        tagType: kFlvTagTypeVideo,
        timestamp: 900,
        isKeyframe: true,
        isSequenceHeader: false,
      ));
      // 音频还没收到任何 tag：任何音频 tag 都算未落后。
      expect(
        timeline.isNotBehind(FlvTag(
          raw: Uint8List(0),
          tagType: kFlvTagTypeAudio,
          timestamp: 100,
          isKeyframe: false,
          isSequenceHeader: false,
        )),
        isTrue,
      );
    });
  });
}
