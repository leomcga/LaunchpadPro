# LaunchpadPro（自用版）

一个用 SwiftUI 写的原生 macOS 启动台（Launchpad）替代品，复刻 LaunchOS Pro 的功能。全部功能默认解锁，无账号 / 无联网 / 无授权校验。

## 使用
- **唤起启动器**：`⌥ Option + 空格`（全局快捷键），或点菜单栏的 ▦ 图标
- **菜单栏右键**：切换竖向滚动 / 触发角 / 每行图标数 / 重新扫描 / 显示隐藏的 App / 退出
- **搜索**：唤起后直接打字过滤
- **打开 App**：单击图标
- **建文件夹**：把一个图标拖到另一个图标上
- **拖动排序**：拖动图标到目标位置
- **右键图标**：打开 / 重命名 / 在访达显示 / 隐藏 / 卸载（移到废纸篓）
- **关闭**：Esc 或点空白处

## 首次使用要授权（系统设置 → 隐私与安全性）
- **辅助功能 / 输入监控**：触发角（hot corner）需要监听全局鼠标，首次可能提示授权。
  全局快捷键用的是 Carbon HotKey，一般不需要授权。
- 若快捷键或触发角没反应，去「隐私与安全性 → 辅助功能」把 LaunchpadPro 打开。

## 已装位置
- App：`/Applications/LaunchpadPro.app`
- 已加为登录项（开机自启，隐藏运行）
- 布局 / 重命名 / 隐藏记录：`~/Library/Application Support/LaunchpadPro/layout.json`

## 重新构建
```bash
cd ~/LaunchpadPro
./bundle.sh                 # 编译 + 打包到 build/LaunchpadPro.app
cp -R build/LaunchpadPro.app /Applications/   # 覆盖安装
```

## 源码结构（Sources/LaunchpadPro/）
- `AppScanner.swift` — 扫描 /Applications 等目录，取图标/名称
- `LaunchModel.swift` — 状态、布局、文件夹、重命名、隐藏、持久化
- `GridViews.swift` — 网格 / 图标 / 文件夹 / 搜索 / 拖拽
- `OverlayWindow.swift` — 全屏覆盖窗口
- `HotKey.swift` — 全局快捷键（Carbon）
- `AppDelegate.swift` — 菜单栏、触发角、快捷键接线
