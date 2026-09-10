import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';

class NetImage extends StatelessWidget {
  final String picUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final double borderRadius;
  const NetImage(this.picUrl,
      {this.width,
      this.height,
      this.fit = BoxFit.cover,
      this.borderRadius = 0,
      super.key});

  @override
  Widget build(BuildContext context) {
    if (picUrl.isEmpty) {
      return Image.asset(
        'assets/images/logo.png',
        width: width,
        height: height,
      );
    }
    var pic = picUrl;
    if (pic.startsWith("//")) {
      pic = 'https:$pic';
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ExtendedImage.network(
        pic,
        fit: fit,
        height: height,
        width: width,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(borderRadius),
        loadStateChanged: (e) {
          // 加载中/失败时保持原有尺寸（封面 110 高），
          // 否则卡片会缩成一个小图标、行高参差、布局错乱
          final icon = switch (e.extendedImageLoadState) {
            LoadState.loading => Icons.image,
            LoadState.failed => Icons.broken_image,
            _ => null,
          };
          if (icon == null) {
            return null;
          }
          return SizedBox(
            width: width,
            height: height,
            child: Icon(
              icon,
              color: Colors.grey,
              size: 24,
            ),
          );
        },
      ),
    );
  }
}
