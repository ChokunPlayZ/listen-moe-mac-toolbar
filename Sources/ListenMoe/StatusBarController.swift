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
        button.setAccessibilityHelp("Click to open the player. Right-click for song info and controls.")
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
        // A fresh view opens at the song info, even after scrolling through saved songs.
        let host = NSHostingController(rootView: PlayerView(radio: radio))
        host.sizingOptions = []
        let availableHeight = button.window?.screen?.visibleFrame.height ?? 800
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 356, height: min(host.view.fittingSize.height, availableHeight - 16))
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func menuWillOpen(_ menu: NSMenu) {
        prepareForPresentation()
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

    @objc func togglePlayback() { radio.togglePlayback() }
    @objc func toggleMute() { radio.isMuted.toggle() }
    @objc func toggleSave() { radio.toggleSave() }
    @objc func copySong() {
        if let track = radio.track { radio.copyTrack(track) }
    }
    @objc func selectStation(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let station = Station(rawValue: value) {
            radio.select(station)
        }
    }
    @objc func openWebsite() { radio.openWebsite() }
    @objc func openOrigin() { radio.openOrigin() }
    @objc func openDiscordSettings() {
        contextMenu.cancelTracking()
        Task { @MainActor [weak self] in self?.radio.openDiscordSettings() }
    }
}

@MainActor
final class StatusContextMenu: NSMenu {
    private let radio: RadioModel
    private let playbackItem = NSMenuItem(title: "Play Radio", action: #selector(StatusBarController.togglePlayback), keyEquivalent: " ")
    private let muteItem = NSMenuItem(title: "Mute", action: #selector(StatusBarController.toggleMute), keyEquivalent: "")
    private let saveItem = NSMenuItem(title: "Save Current Song", action: #selector(StatusBarController.toggleSave), keyEquivalent: "")
    private let copyItem = NSMenuItem(title: "Copy Song & Artist", action: #selector(StatusBarController.copySong), keyEquivalent: "")
    private let originItem = NSMenuItem(title: "View Source on Wikidata", action: #selector(StatusBarController.openOrigin), keyEquivalent: "")
    private var stationItems: [Station: NSMenuItem] = [:]

    init(radio: RadioModel, target: AnyObject) {
        self.radio = radio
        super.init(title: "LISTEN.moe")
        autoenablesItems = false

        let header = NSMenuItem()
        let headerView = NSHostingView(rootView: NowPlayingMenuView(radio: radio))
        headerView.frame = NSRect(origin: .zero, size: headerView.fittingSize)
        header.view = headerView
        header.isEnabled = false
        addItem(header)
        let controlsItem = NSMenuItem()
        let controlsView = NSHostingView(rootView: MenuPlaybackView(radio: radio, openPlayer: { [weak target] in
            (target as? StatusBarController)?.openPlayer()
        }))
        controlsView.frame = NSRect(origin: .zero, size: controlsView.fittingSize)
        controlsItem.view = controlsView
        addItem(controlsItem)
        let volumeItem = NSMenuItem()
        let volumeView = NSHostingView(rootView: MenuVolumeView(radio: radio))
        volumeView.frame = NSRect(origin: .zero, size: volumeView.fittingSize)
        volumeItem.view = volumeView
        addItem(volumeItem)
        addItem(.separator())
        let showPlayer = NSMenuItem(title: "Show Player", action: #selector(StatusBarController.openPlayer), keyEquivalent: "")
        addItem(showPlayer)
        playbackItem.keyEquivalentModifierMask = []
        for item in [playbackItem, muteItem, saveItem, copyItem, originItem] { addItem(item) }
        addItem(.separator())

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
        addItem(stationItem)
        addItem(NSMenuItem(title: "Visit LISTEN.moe", action: #selector(StatusBarController.openWebsite), keyEquivalent: ""))
        addItem(NSMenuItem(title: "Discord Rich Presence…", action: #selector(StatusBarController.openDiscordSettings), keyEquivalent: ""))
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
        playbackItem.title = radio.playbackState.isActive ? "Pause Radio" : "Play Radio"
        muteItem.state = radio.isMuted ? .on : .off
        saveItem.isEnabled = radio.track != nil
        saveItem.state = radio.isCurrentTrackSaved ? .on : .off
        copyItem.isEnabled = radio.track != nil
        originItem.isEnabled = radio.origins.contains { $0.catalogURL != nil }
        for (station, item) in stationItems { item.state = radio.station == station ? .on : .off }
    }
}
