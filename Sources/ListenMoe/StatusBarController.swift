import AppKit
import Combine
import RadioCore
import SwiftUI

enum StatusItemInteraction {
    case player, contextMenu

    static func resolve(type: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags = []) -> Self {
        if type == .rightMouseUp || (type == .leftMouseUp && modifiers.contains(.control)) {
            return .contextMenu
        }
        return .player
    }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let radio: RadioModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private lazy var contextMenu = StatusContextMenu(radio: radio, target: self)
    private var observation: AnyCancellable?

    init(radio: RadioModel) {
        self.radio = radio
        super.init()
        statusItem.autosaveName = "ListenMoeStatusItem"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.animates = false
        contextMenu.delegate = self
        updateStatusItem()
        observation = radio.objectWillChange.sink { [weak self] _ in
            // Published changes arrive before the new value is assigned.
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
                self?.contextMenu.refresh()
            }
        }
    }

    func shutdown() {
        observation?.cancel()
        popover.performClose(nil)
        contextMenu.delegate = nil
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: radio.playbackState.isActive ? "waveform" : "radio",
            accessibilityDescription: radio.menuBarTooltip
        )
        image?.isTemplate = true
        button.image = image
        if radio.showMenuBarTitle, let track = radio.track {
            button.title = " " + String(track.displayTitle(romanized: radio.romanized).prefix(24))
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        button.toolTip = radio.menuBarTooltip
        button.setAccessibilityLabel(radio.menuBarTooltip)
        button.setAccessibilityHelp("Click to open the player. Right-click for settings and app actions.")
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        switch StatusItemInteraction.resolve(type: event?.type, modifiers: event?.modifierFlags ?? []) {
        case .player:
            popover.isShown ? popover.performClose(nil) : showPlayer()
        case .contextMenu:
            popover.performClose(nil)
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
        }
    }

    private func prepareForPresentation() {
        radio.refreshLoginStatus()
        if radio.connectionState == .disconnected || radio.connectionState == .reconnecting {
            radio.reconnectMetadata()
        }
    }

    private func showPlayer() {
        guard let button = statusItem.button else { return }
        prepareForPresentation()
        let availableHeight = button.window?.screen?.visibleFrame.height ?? 800
        // Only library lists scroll; the player grows to fit, within the screen.
        let host = NSHostingController(rootView: PlayerView(
            radio: radio, maximumHeight: availableHeight - 16
        ) { [weak popover] size in
            if popover?.contentSize != size { popover?.contentSize = size }
        })
        host.sizingOptions = []
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func menuWillOpen(_ menu: NSMenu) {
        radio.refreshLoginStatus()
        contextMenu.refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        // Leaving a menu attached would make subsequent left-clicks open it too.
        statusItem.menu = nil
    }

    @objc func openPlayer() {
        // Let menu tracking finish before presenting the popover.
        contextMenu.cancelTracking()
        Task { @MainActor [weak self] in self?.showPlayer() }
    }

    @objc func toggleLaunchAtLogin() {
        radio.setLaunchAtLogin(!radio.launchAtLogin)
        if radio.settingsError != nil { openPlayer() }
    }
    @objc func toggleAutoplay() { radio.autoplay.toggle() }
    @objc func toggleMenuBarTitle() { radio.showMenuBarTitle.toggle() }
    @objc func toggleRomanized() { radio.romanized.toggle() }
    @objc func toggleOriginLookup() { radio.autoDetectOrigins.toggle() }
    @objc func selectStation(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let station = Station(rawValue: value) {
            radio.select(station)
        }
    }
    @objc func openWebsite() { radio.openWebsite() }
    @objc func reconnectMetadata() { radio.reconnectMetadata() }
    @objc func openDiscordSettings() {
        contextMenu.cancelTracking()
        Task { @MainActor [weak self] in self?.radio.openDiscordSettings() }
    }
}

@MainActor
final class StatusContextMenu: NSMenu {
    private let radio: RadioModel
    private let loginItem = NSMenuItem(title: "Launch at login", action: #selector(StatusBarController.toggleLaunchAtLogin), keyEquivalent: "")
    private let autoplayItem = NSMenuItem(title: "Play on launch", action: #selector(StatusBarController.toggleAutoplay), keyEquivalent: "")
    private let titleItem = NSMenuItem(title: "Song title in menu bar", action: #selector(StatusBarController.toggleMenuBarTitle), keyEquivalent: "")
    private let romanizedItem = NSMenuItem(title: "Romanized titles & names", action: #selector(StatusBarController.toggleRomanized), keyEquivalent: "")
    private let originsItem = NSMenuItem(title: "Identify anime / game / VN origins", action: #selector(StatusBarController.toggleOriginLookup), keyEquivalent: "")
    private var stationItems: [Station: NSMenuItem] = [:]

    init(radio: RadioModel, target: AnyObject) {
        self.radio = radio
        super.init(title: "LISTEN.moe")
        autoenablesItems = false

        let showPlayer = NSMenuItem(title: "Show Player", action: #selector(StatusBarController.openPlayer), keyEquivalent: "")
        addItem(showPlayer)
        addItem(.separator())

        let settings = NSMenu(title: "Settings")
        settings.autoenablesItems = false
        let stations = NSMenu(title: "Station")
        stations.autoenablesItems = false
        for station in Station.allCases {
            let item = NSMenuItem(title: station.name, action: #selector(StatusBarController.selectStation(_:)), keyEquivalent: "")
            item.representedObject = station.rawValue
            item.target = target
            stations.addItem(item)
            stationItems[station] = item
        }
        let stationItem = NSMenuItem(title: "Station", action: nil, keyEquivalent: "")
        stationItem.submenu = stations
        settings.addItem(stationItem)
        settings.addItem(.separator())
        for item in [loginItem, autoplayItem, titleItem, romanizedItem, originsItem] {
            item.target = target
            settings.addItem(item)
        }
        settings.addItem(.separator())
        let discordItem = NSMenuItem(title: "Discord Rich Presence…", action: #selector(StatusBarController.openDiscordSettings), keyEquivalent: "")
        discordItem.target = target
        settings.addItem(discordItem)
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settings
        addItem(settingsItem)
        addItem(NSMenuItem(title: "Visit LISTEN.moe", action: #selector(StatusBarController.openWebsite), keyEquivalent: ""))
        addItem(NSMenuItem(title: "Reconnect song info", action: #selector(StatusBarController.reconnectMetadata), keyEquivalent: ""))
        addItem(.separator())
        let quit = NSMenuItem(title: "Quit LISTEN.moe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in items where item.action != nil { item.target = target }
        quit.target = NSApp
        addItem(quit)
        refresh()
    }

    required init(coder: NSCoder) {
        fatalError("StatusContextMenu is created programmatically")
    }

    func refresh() {
        loginItem.state = radio.launchAtLogin ? .on : .off
        autoplayItem.state = radio.autoplay ? .on : .off
        titleItem.state = radio.showMenuBarTitle ? .on : .off
        romanizedItem.state = radio.romanized ? .on : .off
        originsItem.state = radio.autoDetectOrigins ? .on : .off
        for (station, item) in stationItems { item.state = radio.station == station ? .on : .off }
    }
}
