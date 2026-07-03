import SwiftUI
import AppKit

// MARK: - Settings window controller

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: LaunchModel, onHotCornersChanged: @escaping () -> Void, onLaunchAtLoginChanged: @escaping () -> Void) {
        let view = SettingsView(model: model,
                                onHotCornersChanged: onHotCornersChanged,
                                onLaunchAtLoginChanged: onLaunchAtLoginChanged)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "LaunchpadPro 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Settings UI

struct SettingsView: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared
    var onHotCornersChanged: () -> Void
    var onLaunchAtLoginChanged: () -> Void

    var body: some View {
        TabView {
            GeneralTab(settings: settings,
                       onHotCornersChanged: onHotCornersChanged,
                       onLaunchAtLoginChanged: onLaunchAtLoginChanged)
                .tabItem { Label("通用", systemImage: "gearshape") }
            InterfaceTab(settings: settings, model: model)
                .tabItem { Label("界面", systemImage: "square.grid.2x2") }
            AppsTab(model: model)
                .tabItem { Label("Apps", systemImage: "app.badge") }
            AdvancedTab(model: model, settings: settings)
                .tabItem { Label("高级", systemImage: "slider.horizontal.3") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: - 通用 (activation & launch)

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    var onHotCornersChanged: () -> Void
    var onLaunchAtLoginChanged: () -> Void

    var body: some View {
        Form {
            Section("快捷键") {
                Picker("全局快捷键", selection: $settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.label).tag(preset.rawValue)
                    }
                }
                Text("按快捷键可打开 / 关闭启动器。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("触发角") {
                Toggle("移动到屏幕角落时唤起", isOn: $settings.hotCornersEnabled)
                    .onChange(of: settings.hotCornersEnabled) { _, _ in onHotCornersChanged() }
                Picker("触发的角落", selection: $settings.hotCorner) {
                    Text("左上").tag(0); Text("右上").tag(1)
                    Text("左下").tag(2); Text("右下").tag(3)
                }
                .disabled(!settings.hotCornersEnabled)
                Text("触发角需在「系统设置 → 隐私与安全性 → 辅助功能」中授权。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("启动") {
                Toggle("开机自动启动", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, _ in onLaunchAtLoginChanged() }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 6)
    }
}

// MARK: - 界面 (layout & appearance)

private struct InterfaceTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: LaunchModel

    var body: some View {
        Form {
            Section("布局") {
                Picker("显示方式", selection: $settings.verticalScroll) {
                    Text("分页（经典启动台）").tag(false)
                    Text("竖向滚动").tag(true)
                }
                .pickerStyle(.radioGroup)

                Picker("排序方式", selection: Binding(
                    get: { settings.sortMode },
                    set: { settings.sortMode = $0; model.applySort() })) {
                    Text("自定义").tag(0)
                    Text("名称").tag(1)
                    Text("添加日期").tag(2)
                }

                Stepper(value: $settings.columns, in: 4...12) {
                    Text("每行图标数：\(settings.columns)")
                }
                Stepper(value: $settings.rows, in: 3...8) {
                    Text("每页行数：\(settings.rows)")
                }
                .disabled(settings.verticalScroll)
            }

            Section("外观") {
                HStack {
                    Text("图标大小")
                    Slider(value: $settings.iconSize, in: 48...120, step: 4)
                    Text("\(Int(settings.iconSize))")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 34)
                }
                HStack {
                    Text("背景变暗")
                    Slider(value: $settings.backgroundDim, in: 0...0.6, step: 0.02)
                    Text("\(Int(settings.backgroundDim * 100))%")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 40)
                }
                Toggle("显示 App 名称", isOn: $settings.showLabels)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 6)
    }
}

// MARK: - Apps (hidden apps)

private struct AppsTab: View {
    @ObservedObject var model: LaunchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已隐藏的 App").font(.headline)
            let hidden = model.apps.filter { model.hiddenApps.contains($0.id) }
            if hidden.isEmpty {
                Text("没有隐藏的 App。在启动器里右键任意图标即可隐藏。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(hidden, id: \.id) { app in
                        HStack {
                            Image(nsImage: AppScanner.icon(for: app))
                                .resizable().frame(width: 22, height: 22)
                            Text(model.displayName(for: app.id))
                            Spacer()
                            Button("显示") { model.unhide(app.id) }
                        }
                    }
                }
                HStack { Spacer(); Button("全部显示") { model.unhideAll() } }
            }
        }
        .padding(18)
    }
}

// MARK: - 高级

private struct AdvancedTab: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("维护") {
                Button("重新扫描已安装的 App") { model.reload() }
                Button("重置布局与文件夹", role: .destructive) { confirmReset() }
            }
            Section("说明") {
                Text("自用版：所有功能默认解锁，无账号、无联网、无授权校验。布局与设置保存在本机。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 6)
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "重置布局？"
        alert.informativeText = "所有文件夹、排序、重命名和隐藏记录都会清除，恢复到默认。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            model.resetLayout()
        }
    }
}

// MARK: - 关于

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("LaunchpadPro").font(.title2).bold()
            Text("版本 1.0（自用版）").foregroundStyle(.secondary)
            Text("macOS 原生启动台替代品，使用 SwiftUI 编写。\n所有 Pro 功能默认解锁。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
