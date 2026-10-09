-keep class org.videolan.libvlc.** { *; }

# 后台播放：AudioService / MediaButtonReceiver 由 AndroidManifest 引用，AGP 一般会自己
# 保住；这里显式钉一遍，免得今后有人调 manifest 或开更激进的收缩就把它们剥掉——
# 表现是 release 包里通知栏完全不出声不出现，debug 包却一切正常。
# 不 keep androidx.media 整个产物：它体积不小，而且真正的收缩风险在资源侧
# （见 res/raw/keep.xml），不在这一层。
-keep class com.ryanheise.audioservice.** { *; }
