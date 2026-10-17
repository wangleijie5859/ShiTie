import AppKit
#if SWIFT_PACKAGE
import ShitieCore
#endif
import SwiftUI

@main
enum ShitieApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var pauseMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        configureMainMenu()
        configureStatusItem()
        model.openSettings = { [weak self] in self?.showSettings() }
        model.start()
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidResignActive(_ notification: Notification) {
        model.selectedID = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !model.drafts.isEmpty {
            let alert = NSAlert()
            alert.messageText = "还有修改未保存"
            alert.informativeText = "返回拾贴保存修改，或放弃未保存的修改后退出。已保存的历史不会受影响。"
            alert.addButton(withTitle: "返回编辑")
            alert.addButton(withTitle: "放弃修改并退出")
            if alert.runModal() == .alertFirstButtonReturn {
                showMainWindow()
                model.revealDraft()
                return .terminateCancel
            }
        }
        Task {
            await model.prepareToQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc private func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "拾贴"
            window.delegate = self
            window.contentView = NSHostingView(rootView: ContentView(model: model))
            window.contentMinSize = NSSize(width: 560, height: 500)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("ShitieSingleColumnWindow")
            mainWindow = window
        }
        if mainWindow?.contentView == nil {
            mainWindow?.contentView = NSHostingView(rootView: ContentView(model: model))
        }
        if mainWindow?.isMiniaturized == true { mainWindow?.deminiaturize(nil) }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === mainWindow {
            // Keep the same window and model, but stop rendering a hidden SwiftUI tree.
            window.contentView = nil
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "拾贴设置"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "拾贴")
        item.button?.toolTip = "拾贴 · 剪贴板历史"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(actionItem("打开拾贴", #selector(showMainWindow)))
        let pause = actionItem("暂停记录", #selector(togglePause))
        pauseMenuItems.append(pause)
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(actionItem("设置…", #selector(showSettings)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出拾贴", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let app = NSMenu(title: "拾贴")
        app.delegate = self
        app.addItem(actionItem("关于拾贴", #selector(showAbout)))
        app.addItem(.separator())
        app.addItem(actionItem("设置…", #selector(showSettings), key: ","))
        app.addItem(.separator())
        app.addItem(withTitle: "隐藏拾贴", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "退出拾贴", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appendMenu(app, to: main)

        let file = NSMenu(title: "文件")
        file.delegate = self
        file.addItem(actionItem("打开拾贴", #selector(showMainWindow), key: "0"))
        let pause = actionItem("暂停记录", #selector(togglePause), key: "p")
        pause.keyEquivalentModifierMask = [.command, .shift]
        pauseMenuItems.append(pause)
        file.addItem(pause)
        file.addItem(.separator())
        file.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appendMenu(file, to: main)

        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(actionItem("搜索当前分类", #selector(focusSearch), key: "f"))
        appendMenu(edit, to: main)

        let window = NSMenu(title: "窗口")
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window
        appendMenu(window, to: main)
        #if DEBUG
        let debug = NSMenu(title: "调试")
        debug.addItem(actionItem("预览浅色外观", #selector(previewLight)))
        debug.addItem(actionItem("预览深色外观", #selector(previewDark)))
        debug.addItem(actionItem("跟随系统外观", #selector(previewSystem)))
        appendMenu(debug, to: main)
        #endif
        NSApp.mainMenu = main
    }

    private func appendMenu(_ menu: NSMenu, to parent: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        parent.addItem(item)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in pauseMenuItems {
            item.title = model.settings.isPaused ? "恢复记录" : "暂停记录"
            item.isEnabled = model.isReady && !model.isChangingPause
        }
    }

    @objc private func togglePause() { model.togglePause() }
    @objc private func focusSearch() { showMainWindow(); model.focusSearchRequest += 1 }
    @objc private func showAbout() { showSettings() }
    #if DEBUG
    @objc private func previewLight() { NSApp.appearance = NSAppearance(named: .aqua) }
    @objc private func previewDark() { NSApp.appearance = NSAppearance(named: .darkAqua) }
    @objc private func previewSystem() { NSApp.appearance = nil }
    #endif
}
