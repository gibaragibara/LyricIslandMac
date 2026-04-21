import AppKit
import SwiftUI

struct OverlayScreenOption: Identifiable, Hashable {
    let id: String
    let title: String
}

enum OverlayDisplayMode: String, CaseIterable, Identifiable {
    case compact
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            "紧凑模式"
        case .expanded:
            "展开模式"
        }
    }

    var isExpanded: Bool {
        self == .expanded
    }
}

struct OverlayViewModel {
    var title: String
    var subtitle: String
    var artistArtworkURL: String?
    var currentLine: String
    var currentSubline: String?
    var compactPrimaryLine: String
    var compactSecondaryLine: String
    var artworkURL: String?
    var currentProgress: Double
    var nextLine: String?
    var isPlaying: Bool
    var overlayOpacity: Double = 0.96
    var overlayScale: Double = 1.0
    var isExpanded: Bool = false
    var isPointerHovering: Bool = false
    var collapsedWidth: CGFloat = 224
    var collapsedHeight: CGFloat = 24
    var expandedWidth: CGFloat = 500
    var expandedHeight: CGFloat = 128
}

@MainActor
final class OverlayPanelController {
    private var panel: NSPanel?
    private var baseModel: OverlayViewModel?
    private var displayMode: OverlayDisplayMode = .compact
    private var preferredScreenID: String?
    private var isPointerHoveringVisibleSurface = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private static let baseExpandedWidth: CGFloat = 500
    private static let expandedHeight: CGFloat = 126
    private static let hoverFadeOpacity: Double = 0.22

    func show(model: OverlayViewModel) {
        let panel = panel ?? makePanel()
        self.panel = panel
        baseModel = model
        installMouseMonitorsIfNeeded()
        renderCurrentModel()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        updatePointerHovering(force: false)
    }

    func setDisplayMode(_ displayMode: OverlayDisplayMode) {
        guard self.displayMode != displayMode else { return }
        self.displayMode = displayMode
        renderCurrentModel()
    }

    func setPreferredScreenID(_ preferredScreenID: String?) {
        let normalizedID = preferredScreenID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        guard self.preferredScreenID != normalizedID else { return }
        self.preferredScreenID = normalizedID
        renderCurrentModel()
    }

    static func availableScreenOptions() -> [OverlayScreenOption] {
        NSScreen.screens.enumerated().map { index, screen in
            let baseName = screen.localizedName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "显示器 \(index + 1)"
            return OverlayScreenOption(
                id: screen.persistentIdentifier,
                title: "\(index + 1). \(baseName)"
            )
        }
    }

    private func renderCurrentModel() {
        guard let panel, var decorated = baseModel else { return }
        let screen = resolveTargetScreen()
        let collapsed = screen?.notchSize ?? CGSize(width: 224, height: 24)
        let scale = max(0.75, min(1.35, decorated.overlayScale))
        
        let primaryFont = NSFont.systemFont(ofSize: 16 * scale, weight: .semibold)
        let secondaryFont = NSFont.systemFont(ofSize: 12 * scale, weight: .medium)
        let primaryWidth = (decorated.compactPrimaryLine as NSString).size(withAttributes: [.font: primaryFont]).width
        let secondaryWidth = (decorated.compactSecondaryLine as NSString).size(withAttributes: [.font: secondaryFont]).width
        let textWidth = max(primaryWidth, secondaryWidth)
        
        let baseElementWidth = 106.0 * scale + 24.0
        let targetAutoWidth = baseElementWidth + textWidth + 16.0
        
        let hasNotch = (screen?.safeAreaInsets.top ?? 0) > 0
        let minWidth: CGFloat = hasNotch ? (collapsed.width + 100 * scale) : (240 * scale)
        
        let collapsedWidth = min(max(targetAutoWidth, minWidth), 640 * scale)
        let collapsedHeight = max(50, ((screen?.islandClosedHeight ?? 24) + 26) * scale)
        let expandedWidth = min(max(collapsedWidth + (12 * scale), Self.baseExpandedWidth * scale), 680 * scale)
        let expandedHeight = max(108, Self.expandedHeight * scale)

        decorated.isExpanded = displayMode.isExpanded
        decorated.isPointerHovering = isPointerHoveringVisibleSurface
        if decorated.isPointerHovering {
            decorated.overlayOpacity = min(decorated.overlayOpacity, Self.hoverFadeOpacity)
        }
        decorated.collapsedWidth = collapsedWidth
        decorated.collapsedHeight = collapsedHeight
        decorated.expandedWidth = expandedWidth
        decorated.expandedHeight = expandedHeight

        if let host = panel.contentView as? NSHostingView<OverlayPillView> {
            host.rootView = OverlayPillView(model: decorated)
        }

        let panelWidth = max(700.0 * scale, expandedWidth)
        layout(panel: panel, on: screen, expandedWidth: panelWidth, expandedHeight: expandedHeight)
        updatePointerHovering(force: isPointerInsideVisibleSurface())
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.baseExpandedWidth, height: Self.expandedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true

        panel.contentView = NSHostingView(rootView: OverlayPillView(model: .init(
            title: "歌词岛",
            subtitle: "等待播放状态",
            artistArtworkURL: nil,
            currentLine: "暂无歌词",
            currentSubline: nil,
            compactPrimaryLine: "暂无歌词",
            compactSecondaryLine: "等待播放状态",
            artworkURL: nil,
            currentProgress: 0,
            nextLine: nil,
            isPlaying: false
        )))
        return panel
    }

    private func layout(panel: NSPanel, on screen: NSScreen?, expandedWidth: CGFloat, expandedHeight: CGFloat) {
        guard let screen else { return }
        let width = expandedWidth
        let height = expandedHeight
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func resolveTargetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        if let preferredScreenID,
           let preferredScreen = screens.first(where: { $0.persistentIdentifier == preferredScreenID }) {
            return preferredScreen
        }
        if let main = NSScreen.main {
            return main
        }
        if let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }
        return screens[0]
    }

    private func installMouseMonitorsIfNeeded() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp
        ]

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                self?.updatePointerHovering(force: self?.isPointerInsideVisibleSurface() ?? false)
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.updatePointerHovering(force: self?.isPointerInsideVisibleSurface() ?? false)
            }
            return event
        }
    }

    private func updatePointerHovering(force newValue: Bool) {
        guard isPointerHoveringVisibleSurface != newValue else { return }
        isPointerHoveringVisibleSurface = newValue
        guard panel?.isVisible == true else { return }
        renderCurrentModel()
    }

    private func isPointerInsideVisibleSurface() -> Bool {
        guard let panel, panel.isVisible, let model = baseModel else { return false }
        let pointer = NSEvent.mouseLocation
        return visibleSurfaceFrame(in: panel.frame, model: model).contains(pointer)
    }

    private func visibleSurfaceFrame(in panelFrame: NSRect, model: OverlayViewModel) -> NSRect {
        let isExpanded = displayMode.isExpanded
        let surfaceWidth = isExpanded ? model.expandedWidth : model.collapsedWidth
        let surfaceHeight = isExpanded ? model.expandedHeight : max(72, model.collapsedHeight)
        let originX = panelFrame.midX - surfaceWidth / 2
        let originY = panelFrame.maxY - surfaceHeight
        return NSRect(x: originX, y: originY, width: surfaceWidth, height: surfaceHeight)
    }
}

extension NSScreen {
    var persistentIdentifier: String {
        if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return localizedName
    }

    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 224, height: 38)
        }

        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftPadding - rightPadding + 4
        return CGSize(width: notchWidth, height: notchHeight)
    }

    var topStatusBarHeight: CGFloat {
        let reservedTopInset = max(0, frame.maxY - visibleFrame.maxY)
        if reservedTopInset > 0 {
            return reservedTopInset
        }
        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top
        }
        return 24
    }

    var islandClosedHeight: CGFloat {
        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top
        }
        return topStatusBarHeight
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
