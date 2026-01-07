## 1. 项目清理与简化

### 1.1 删除不需要的平台目录

* 删除 `simple_live_app/android/` 目录

* 删除 `simple_live_app/ios/` 目录

* 删除 `simple_live_app/macos/` 目录

* 删除 `simple_live_app/linux/` 目录

* 删除 `simple_live_tv_app/` 整个目录（TV版本）

* 删除 `simple_live_console/` 整个目录（控制台版本）（如果不需要）

### 1.2 更新pubspec.yaml

* 移除仅针对移动平台的依赖（如：permission\_handler、image\_gallery\_saver\_plus、screen\_brightness、auto\_orientation\_v2等）

* 保留核心功能依赖和Windows平台需要的依赖

* 更新flutter\_launcher\_icons配置，只保留Windows相关设置

### 1.3 更新GitHub Actions配置

* 修改 `.github/workflows/` 下的所有yaml文件，只保留Windows平台的编译流程

* 移除Android、iOS、macOS、Linux相关的编译步骤

## 2. WinUI 3迁移准备

### 2.1 了解当前Flutter Windows嵌入层

* 当前使用的是基于Win32的嵌入层

* 主要文件在 `simple_live_app/windows/` 目录下

### 2.2 WinUI 3环境配置

* 确保GitHub Actions的windows-latest环境支持WinUI 3

* 安装必要的Windows App SDK组件

## 3. 实现WinUI 3嵌入

### 3.1 创建WinUI 3项目结构

* 在 `simple_live_app/windows/` 目录下创建WinUI 3相关文件

* 更新CMakeLists.txt以支持WinUI 3

### 3.2 实现Flutter与WinUI 3的集成

* 使用Windows App SDK和WinUI 3创建应用窗口

* 将Flutter视图嵌入到WinUI 3窗口中

* 实现必要的平台通道以支持WinUI 3特有的功能

### 3.3 更新依赖和链接库

* 添加WinUI 3和Windows App SDK的依赖

* 更新target\_link\_libraries以包含WinUI 3相关库

### 3.4 调整资源和清单文件

* 更新应用清单以支持WinUI 3

* 确保资源文件（如图标）与WinUI 3兼容

## 4. 测试与调试

### 4.1 本地测试

* 在本地Windows环境中测试WinUI 3版本

* 确保核心功能正常工作

### 4.2 GitHub Actions测试

* 推送修改到GitHub，测试Actions编译流程

* 确保Windows版本能够成功编译并生成安装包

## 5. 优化与完善

### 5.1 WinUI 3特性集成

* 根据需要集成WinUI 3特有的UI组件和功能

* 优化应用在不同Windows版本上的表现

### 5.2 性能优化

* 优化Flutter与WinUI 3之间的通信

* 确保应用流畅运行

## 6. 最终验证

### 6.1 功能验证

* 验证所有核心功能在WinUI 3版本上正常工作

* 确保与原Flutter版本功能一致

### 6.2 兼容性验证

* 测试在不同Windows版本上的兼容性

* 确保应用能够在目标Windows版本上正常运行

## 注意事项

1. WinUI 3需要Windows 11 24h2或更高版本
2. 迁移过程中需要注意Flutter与WinUI 3之间的生命周期管理
3. 需要更新所有平台特定的代码以适应WinUI 3环境
4. GitHub Actions的windows-latest环境已包含WinUI 3开发所需的工具链，可以正常编译
5. 迁移后，应用将使用WinUI 3的窗口管理和UI渲染，提供更现代的Windows应用体验

通过以上步骤，我们可以将当前的Flutter应用Windows端从Win32切换到WinUI 3，同时保留在GitHub Actions上的编译能力。
