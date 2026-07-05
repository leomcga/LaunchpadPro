import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(
        model: LaunchModel,
        onHotCornersChanged: @escaping () -> Void,
        onLaunchAtLoginChanged: @escaping () -> Void,
        onMenuBarIconChanged: @escaping () -> Void
    ) {
        let view = SettingsView(
            model: model,
            onHotCornersChanged: onHotCornersChanged,
            onLaunchAtLoginChanged: onLaunchAtLoginChanged,
            onMenuBarIconChanged: onMenuBarIconChanged
        )
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "LaunchpadPro 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 540, height: 500))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct SettingsView: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings = AppSettings.shared

    var onHotCornersChanged: () -> Void
    var onLaunchAtLoginChanged: () -> Void
    var onMenuBarIconChanged: () -> Void

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $selectedTab)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()
                .opacity(0.45)

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsTab(
                settings: settings,
                onHotCornersChanged: onHotCornersChanged,
                onLaunchAtLoginChanged: onLaunchAtLoginChanged,
                onMenuBarIconChanged: onMenuBarIconChanged
            )
        case .interface:
            InterfaceSettingsTab(model: model, settings: settings)
        case .apps:
            AppsSettingsTab(model: model)
        case .advanced:
            AdvancedSettingsTab(model: model)
        case .about:
            AboutSettingsTab()
        }
    }
}

private enum SettingsTab: CaseIterable, Identifiable {
    case general
    case interface
    case apps
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "通用"
        case .interface: return "界面"
        case .apps: return "Apps"
        case .advanced: return "高级"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .interface: return "square.grid.2x2"
        case .apps: return "app.badge"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 3) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? Color.white : Color.primary.opacity(0.72))
                    .frame(width: 88, height: 30)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.accentColor)
                                .shadow(color: Color.accentColor.opacity(0.24), radius: 5, y: 2)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var onHotCornersChanged: () -> Void
    var onLaunchAtLoginChanged: () -> Void
    var onMenuBarIconChanged: () -> Void

    var body: some View {
        Form {
            Section("快捷键") {
                Picker("全局快捷键", selection: $settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.label).tag(preset.rawValue)
                    }
                }
            }

            Section("触发角") {
                Toggle("移动到屏幕角落时唤起", isOn: $settings.hotCornersEnabled)
                    .onChange(of: settings.hotCornersEnabled) { _, _ in onHotCornersChanged() }

                Picker("触发的角落", selection: $settings.hotCorner) {
                    Text("左上").tag(0)
                    Text("右上").tag(1)
                    Text("左下").tag(2)
                    Text("右下").tag(3)
                }
                .disabled(!settings.hotCornersEnabled)
                .onChange(of: settings.hotCorner) { _, _ in onHotCornersChanged() }

                Text("触发角需要辅助功能权限；快捷键一般不需要。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("启动") {
                Toggle("开机自动启动", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, _ in onLaunchAtLoginChanged() }

                Toggle("显示菜单栏图标", isOn: $settings.showMenuBarIcon)
                    .onChange(of: settings.showMenuBarIcon) { _, _ in onMenuBarIconChanged() }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 6)
    }
}

private struct InterfaceSettingsTab: View {
    @ObservedObject var model: LaunchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("布局") {
                Picker("显示方式", selection: $settings.verticalScroll) {
                    Text("分页").tag(false)
                    Text("竖向滚动").tag(true)
                }
                .pickerStyle(.radioGroup)

                Picker("排序方式", selection: Binding(
                    get: { settings.sortMode },
                    set: {
                        settings.sortMode = $0
                        model.applySort()
                    }
                )) {
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
                    Slider(value: $settings.iconSize, in: 50...120, step: 2)
                    Text("\(Int(settings.iconSize))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34)
                }

                HStack {
                    Text("背景变暗")
                    Slider(value: $settings.backgroundDim, in: 0...0.62, step: 0.02)
                    Text("\(Int(settings.backgroundDim * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42)
                }

                Toggle("显示 App 名称", isOn: $settings.showLabels)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 6)
    }
}

private struct AppsSettingsTab: View {
    @ObservedObject var model: LaunchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已隐藏的 App")
                .font(.headline)

            let hidden = model.apps.filter { model.hiddenApps.contains($0.id) }

            if hidden.isEmpty {
                Text("没有隐藏的 App。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(hidden, id: \.id) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: AppScanner.icon(for: app))
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text(model.displayName(for: app.id))
                            Spacer()
                            Button("显示") { model.unhide(app.id) }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("全部显示") { model.unhideAll() }
                }
            }
        }
        .padding(18)
    }
}

private struct AdvancedSettingsTab: View {
    @ObservedObject var model: LaunchModel

    var body: some View {
        Form {
            Section("布局记忆") {
                ForEach(0..<3, id: \.self) { slot in
                    LayoutMemoryRow(model: model, slot: slot)
                }
            }

            Section("维护") {
                Button("重新扫描已安装的 App") { model.reload() }
                Button("重置布局、文件夹、重命名和隐藏", role: .destructive) {
                    confirmReset()
                }
            }

            Section("数据") {
                Text("~/Library/Application Support/LaunchpadPro/layout.json")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 6)
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "重置 LaunchpadPro？"
        alert.informativeText = "文件夹、排序、重命名和隐藏记录都会清除。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            model.resetLayout()
        }
    }
}

private struct LayoutMemoryRow: View {
    @ObservedObject var model: LaunchModel
    let slot: Int

    private var memory: LayoutMemory? {
        model.layoutMemory(slot: slot)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("布局 \(slot + 1)")
                    .font(.system(size: 13, weight: .semibold))
                Text(memory.map(savedDescription) ?? "未保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(memory == nil ? "保存" : "覆盖") {
                model.saveLayoutMemory(slot: slot)
            }

            Button("恢复") {
                model.restoreLayoutMemory(slot: slot)
            }
            .disabled(memory == nil)

            Button("删除", role: .destructive) {
                model.deleteLayoutMemory(slot: slot)
            }
            .disabled(memory == nil)
        }
    }

    private func savedDescription(_ memory: LayoutMemory) -> String {
        Date(timeIntervalSince1970: memory.savedAt).formatted(date: .numeric, time: .shortened)
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 12) {
            if let icon = AppBranding.icon(size: NSSize(width: 72, height: 72)) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
            }

            Text("LaunchpadPro")
                .font(.title2)
                .bold()

            Text("版本 1.0")
                .foregroundStyle(.secondary)

            Text("原生 macOS 启动台替代品。纯本地运行，无账号、无联网、无授权校验。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
