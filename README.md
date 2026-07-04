# LaunchpadProCodex

Codex 版 macOS 原生启动台替代品。目标是对齐原需求里的 LaunchpadPro：全屏分页网格、搜索、文件夹、拖拽排序、右键管理、菜单栏常驻、全局快捷键、触发角、开机自启与本地持久化。

## 使用

- 唤起启动器：`⌥ Option + 空格`，或点击菜单栏网格图标
- 搜索：打开后直接输入
- 打开 App：单击图标
- 拖拽排序：拖动图标到目标位置
- 建文件夹：把一个 App 拖到另一个 App 中心
- 文件夹：单击打开，点标题重命名，文件夹内可排序，拖出可移出
- 右键 App：打开、重命名、访达显示、隐藏、卸载到废纸篓
- 关闭：`Esc` 或点击空白处

## 构建

```bash
cd ~/本地/Project_Git/LaunchpadProCodex
swift build -c release
./bundle.sh
```

`.app` 输出在：

```text
build/LaunchpadProCodex.app
```

## 部署

```bash
./deploy.sh
```

部署到 `/Applications/LaunchpadProCodex.app`。Bundle ID 与 Claude 版不同：`com.leo.launchpadprocodex`，不会覆盖 `/Applications/LaunchpadPro.app`。

## 本地数据

- 布局、文件夹、重命名、隐藏：`~/Library/Application Support/LaunchpadProCodex/layout.json`
- 设置：`UserDefaults`，key 前缀 `codex.`

## 代码结构

- `AppDelegate.swift`：菜单栏、快捷键、触发角、登录项
- `OverlayController.swift`：全屏覆盖窗口、窗口层级毛玻璃、滚轮/触控板翻页
- `LaunchModel.swift`：App、文件夹、布局和持久化
- `LauncherViews.swift`：根视图、搜索栏、图标、文件夹浮层
- `PagedLauncherView.swift`：分页网格、拖拽排序、建文件夹、拖出文件夹落点
- `SettingsView.swift`：设置窗口
- `AppScanner.swift`：扫描本机 App 和图标缓存
