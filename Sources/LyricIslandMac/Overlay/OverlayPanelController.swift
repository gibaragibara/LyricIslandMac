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

struct OverlayViewModel: Equatable {
    var title: String
    var subtitle: String
    var artistArtworkURL: String?
    var currentLine: String
    var currentSubline: String?
    var compactPrimaryLine: String
    var compactSecondaryLine: String
    var artworkURL: String?
    var currentProgress: Double
    var currentLyricLine: LyricLine?
    var playbackProgressAnchorMs: Int
    var playbackProgressAnchorDate: Date
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
    var hasNotch: Bool = false
    var safeAreaTop: CGFloat = 0
}

private extension OverlayViewModel {
    static let placeholder = OverlayViewModel(
        title: "歌词岛",
        subtitle: "等待播放状态",
        artistArtworkURL: nil,
        currentLine: "暂无歌词",
        currentSubline: nil,
        compactPrimaryLine: "暂无歌词",
        compactSecondaryLine: "等待播放状态",
        artworkURL: nil,
        currentProgress: 0,
        currentLyricLine: nil,
        playbackProgressAnchorMs: 0,
        playbackProgressAnchorDate: Date(),
        nextLine: nil,
        isPlaying: false
    )
}

@MainActor
private final class OverlayModelStore: ObservableObject {
    @Published var model: OverlayViewModel

    init(model: OverlayViewModel) {
        self.model = model
    }
}

private struct OverlayRootView: View {
    @ObservedObject var store: OverlayModelStore

    var body: some View {
        OverlayPillView(model: store.model)
    }
}

@MainActor
final class OverlayPanelController {
    private var panel: NSPanel?
    private let modelStore = OverlayModelStore(model: .placeholder)
    private var baseModel: OverlayViewModel?
    private var renderedModel: OverlayViewModel?
    private var displayMode: OverlayDisplayMode = .compact
    private var preferredScreenID: String?
    private var isPointerHoveringVisibleSurface = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private static let baseExpandedWidth: CGFloat = 500
    private static let expandedHeight: CGFloat = 126
    private static let hoverFadeOpacity: Double = 0.22
    private var cachedTextKey: String = ""
    private var cachedScale: Double = 0
    private var cachedWidths: CachedTextWidths = .zero

    private struct CachedTextWidths {
        var compactPrimary: CGFloat = 0
        var compactSecondary: CGFloat = 0
        var expandedLine: CGFloat = 0
        var expandedSubline: CGFloat = 0
        var expandedNextLine: CGFloat = 0
        var title: CGFloat = 0
        var subtitle: CGFloat = 0
        static let zero = CachedTextWidths()
    }

    func show(model: OverlayViewModel) {
        let panel = panel ?? makePanel()
        self.panel = panel
        baseModel = model
        installMouseMonitorsIfNeeded()
        renderCurrentModel()
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        renderedModel = nil
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

        let textKey = "\(decorated.compactPrimaryLine)\0\(decorated.compactSecondaryLine)\0\(decorated.currentLine)\0\(decorated.currentSubline ?? "")\0\(decorated.nextLine ?? "")\0\(decorated.title)\0\(decorated.subtitle)"
        if textKey != cachedTextKey || scale != cachedScale {
            cachedTextKey = textKey
            cachedScale = scale
            let primaryFont = NSFont.systemFont(ofSize: 16 * scale, weight: .semibold)
            let secondaryFont = NSFont.systemFont(ofSize: 12 * scale, weight: .medium)
            let expandedPrimaryFont = NSFont.systemFont(ofSize: 15 * scale, weight: .semibold)
            let expandedSublineFont = NSFont.systemFont(ofSize: 11.5 * scale, weight: .medium)
            let expandedNextLineFont = NSFont.systemFont(ofSize: 10.5 * scale, weight: .regular)
            let titleFont = NSFont.systemFont(ofSize: 13 * scale, weight: .semibold)
            let subtitleFont = NSFont.systemFont(ofSize: 10.5 * scale, weight: .regular)
            cachedWidths = CachedTextWidths(
                compactPrimary: (decorated.compactPrimaryLine as NSString).size(withAttributes: [.font: primaryFont]).width,
                compactSecondary: (decorated.compactSecondaryLine as NSString).size(withAttributes: [.font: secondaryFont]).width,
                expandedLine: (decorated.currentLine as NSString).size(withAttributes: [.font: expandedPrimaryFont]).width,
                expandedSubline: ((decorated.currentSubline ?? "") as NSString).size(withAttributes: [.font: expandedSublineFont]).width,
                expandedNextLine: ((decorated.nextLine ?? "") as NSString).size(withAttributes: [.font: expandedNextLineFont]).width,
                title: (decorated.title as NSString).size(withAttributes: [.font: titleFont]).width,
                subtitle: (decorated.subtitle as NSString).size(withAttributes: [.font: subtitleFont]).width
            )
        }
        let w = cachedWidths
        let textWidth = max(w.compactPrimary, w.compactSecondary)

        let baseElementWidth = 106.0 * scale + 24.0
        let targetAutoWidth = baseElementWidth + textWidth + 16.0

        let safeAreaTop = screen?.safeAreaInsets.top ?? 0
        let hasNotch = safeAreaTop > 0
        let minWidth: CGFloat = hasNotch ? (collapsed.width + 140 * scale) : (240 * scale)

        let collapsedWidth = min(max(targetAutoWidth, minWidth), 640 * scale)
        let collapsedHeight = safeAreaTop + 50 * scale

        let headerTextWidth = max(w.title, w.subtitle)
        let maxExpandedTextWidth = max(w.expandedLine, w.expandedSubline, w.expandedNextLine)
        let expandedTargetWidth = max(maxExpandedTextWidth, headerTextWidth + 90 * scale) + 68 * scale

        let expandedWidth = min(max(expandedTargetWidth, collapsedWidth + 24 * scale), 720 * scale)
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
        decorated.hasNotch = hasNotch
        decorated.safeAreaTop = safeAreaTop
        renderedModel = decorated

        if modelStore.model != decorated {
            modelStore.model = decorated
        }

        let panelWidth = max(700.0 * scale, expandedWidth)
        layout(panel: panel, on: screen, expandedWidth: panelWidth, expandedHeight: expandedHeight)
        updatePointerHovering(force: isPointerInsideVisibleSurface())
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.baseExpandedWidth, height: Self.expandedHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .fullScreenDisallowsTiling, .ignoresCycle, .stationary]
        panel.isMovable = false
        panel.ignoresMouseEvents = true

        panel.contentView = NSHostingView(rootView: OverlayRootView(store: modelStore))
        return panel
    }

    private func layout(panel: NSPanel, on screen: NSScreen?, expandedWidth: CGFloat, expandedHeight: CGFloat) {
        guard let screen else { return }
        let width = expandedWidth
        let height = expandedHeight
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        let nextFrame = NSRect(x: x, y: y, width: width, height: height)
        guard !panel.frame.isApproximatelyEqual(to: nextFrame) else { return }
        panel.setFrame(nextFrame, display: false)
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
        guard let panel, panel.isVisible, let model = renderedModel ?? baseModel else { return false }
        let pointer = NSEvent.mouseLocation
        return visibleSurfaceFrame(in: panel.frame, model: model).contains(pointer)
    }

    private func visibleSurfaceFrame(in panelFrame: NSRect, model: OverlayViewModel) -> NSRect {
        let isExpanded = displayMode.isExpanded
        let surfaceWidth = isExpanded ? model.expandedWidth : model.collapsedWidth
        let surfaceHeight = isExpanded ? model.expandedHeight : model.collapsedHeight
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

private extension NSRect {
    func isApproximatelyEqual(to other: NSRect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5
            && abs(origin.y - other.origin.y) < 0.5
            && abs(size.width - other.size.width) < 0.5
            && abs(size.height - other.size.height) < 0.5
    }
}
