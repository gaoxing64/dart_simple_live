package com.slotsun.slive

import com.ryanheise.audioservice.AudioServiceActivity

// 父类从 FlutterActivity 换成 AudioServiceActivity，是为了让 audio_service 在进程被
// 系统回收后重建引擎时，Activity 仍然用**同一个** FlutterEngine（它只覆写了
// provideFlutterEngine()，没有任何生命周期/按键覆写，所以 PiP、返回键行为都不变）。
// 换父类不影响 floating 那套 PiP：插件照常通过 plugin registry 拿到本 activity。
class MainActivity : AudioServiceActivity()
