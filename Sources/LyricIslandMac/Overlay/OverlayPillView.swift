import AppKit
import QuartzCore
import SwiftUI

struct OverlayPillView: View {
    let model: OverlayViewModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            surface
                .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
                .contentShape(surfaceShape)
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .animation(.spring(response: 0.26, dampingFraction: 0.84), value: model.isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: surfaceWidth)
        .animation(.easeInOut(duration: 0.18), value: model.isPointerHovering)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var surface: some View {
        ZStack(alignment: .top) {
            surfaceShape
                .fill(Color.black.opacity(model.overlayOpacity))

            if model.isExpanded {
                expandedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                compactContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .clipShape(surfaceShape)
        .overlay {
            surfaceShape
                .stroke(Color.white.opacity(model.isExpanded ? 0.08 : 0.05), lineWidth: 1)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .center, spacing: scaled(6)) {
            HStack(spacing: scaled(10)) {
                compactLeadingBadge

                VStack(alignment: .leading, spacing: scaled(1)) {
                    Text(model.title)
                        .font(.system(size: scaled(13), weight: .semibold))
                        .lineLimit(1)

                    Text(model.subtitle)
                        .font(.system(size: scaled(10.5), weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: scaled(8))

                CompactArtworkView(urlString: model.artworkURL, overlayScale: max(0.82, model.overlayScale * 0.9))
            }

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            KaraokeLineText(
                text: model.currentLine,
                progress: model.currentProgress,
                lyricLine: model.currentLyricLine,
                playbackProgressAnchorMs: model.playbackProgressAnchorMs,
                playbackProgressAnchorDate: model.playbackProgressAnchorDate,
                isPlaying: model.isPlaying,
                font: .systemFont(ofSize: scaled(15), weight: .semibold),
                alignment: .center
            )

            if let currentSubline = model.currentSubline, !currentSubline.isEmpty {
                Text(currentSubline)
                    .font(.system(size: scaled(11.5), weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
            }

            if let nextLine = model.nextLine, !nextLine.isEmpty {
                Text(nextLine)
                    .font(.system(size: scaled(10.5), weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, scaled(32))
        .padding(.vertical, scaled(9))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var compactContent: some View {
        if model.hasNotch {
            notchCompactContent
        } else {
            originalCompactContent
        }
    }

    private var notchCompactContent: some View {
        ZStack(alignment: .top) {
            // Text below the notch
            VStack(alignment: .center, spacing: 2) {
                KaraokeLineText(
                    text: model.compactPrimaryLine,
                    progress: model.currentProgress,
                    lyricLine: model.currentLyricLine,
                    playbackProgressAnchorMs: model.playbackProgressAnchorMs,
                    playbackProgressAnchorDate: model.playbackProgressAnchorDate,
                    isPlaying: model.isPlaying,
                    font: .systemFont(ofSize: scaled(16), weight: .semibold),
                    alignment: .center
                )

                Text(model.compactSecondaryLine)
                    .font(.system(size: scaled(12), weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(1)
            }
            .padding(.top, model.safeAreaTop + scaled(4))
            .padding(.horizontal, scaled(18))
            
            // Images beside the notch
            HStack {
                compactLeadingBadge
                Spacer()
                CompactArtworkView(urlString: model.artworkURL, overlayScale: model.overlayScale)
            }
            .padding(.horizontal, scaled(18))
            .frame(height: max(50 * model.overlayScale, model.safeAreaTop))
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var originalCompactContent: some View {
        HStack(spacing: 12) {
            compactLeadingBadge

            VStack(alignment: .center, spacing: 2) {
                KaraokeLineText(
                    text: model.compactPrimaryLine,
                    progress: model.currentProgress,
                    lyricLine: model.currentLyricLine,
                    playbackProgressAnchorMs: model.playbackProgressAnchorMs,
                    playbackProgressAnchorDate: model.playbackProgressAnchorDate,
                    isPlaying: model.isPlaying,
                    font: .systemFont(ofSize: scaled(16), weight: .semibold),
                    alignment: .center
                )

                Text(model.compactSecondaryLine)
                    .font(.system(size: scaled(12), weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(1)
            }

            CompactArtworkView(urlString: model.artworkURL, overlayScale: model.overlayScale)
        }
        .padding(.horizontal, scaled(18))
        .padding(.vertical, scaled(10))
    }

    private var compactLeadingBadge: some View {
        ArtistArtworkView(urlString: model.artistArtworkURL, overlayScale: model.overlayScale, isPlaying: model.isPlaying)
    }

    private var surfaceShape: NotchSurfaceShape {
        let targetBottomRadius: CGFloat = model.isExpanded ? 36 : 999
        return NotchSurfaceShape(
            topCornerRadius: (model.isExpanded ? 22 : 10) * model.overlayScale,
            bottomCornerRadius: targetBottomRadius * model.overlayScale
        )
    }

    private var surfaceWidth: CGFloat {
        model.isExpanded ? model.expandedWidth : model.collapsedWidth
    }

    private var surfaceHeight: CGFloat {
        if model.isExpanded {
            return model.expandedHeight
        }
        return model.collapsedHeight
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * model.overlayScale
    }
}

private struct ArtistArtworkView: View {
    let urlString: String?
    let overlayScale: Double
    let isPlaying: Bool

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString), !urlString.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: CGFloat(30 * overlayScale), height: CGFloat(30 * overlayScale))
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: isPlaying
                    ? [Color(red: 0.1, green: 0.88, blue: 0.46), Color(red: 0.02, green: 0.58, blue: 0.31)]
                    : [Color.gray.opacity(0.85), Color.gray.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "person.fill")
                .font(.system(size: CGFloat(12 * overlayScale), weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct KaraokeLineText: View {
    let text: String
    let progress: Double
    let lyricLine: LyricLine?
    let playbackProgressAnchorMs: Int
    let playbackProgressAnchorDate: Date
    let isPlaying: Bool
    let font: NSFont
    var alignment: NSTextAlignment = .center

    var body: some View {
        KaraokeLineRepresentable(
            text: text,
            font: font,
            alignment: alignment,
            staticProgress: progress,
            lyricLine: lyricLine,
            anchorMs: playbackProgressAnchorMs,
            anchorDate: playbackProgressAnchorDate,
            isPlaying: isPlaying
        )
        .frame(maxWidth: .infinity)
    }
}

private struct KaraokeLineRepresentable: NSViewRepresentable {
    let text: String
    let font: NSFont
    let alignment: NSTextAlignment
    let staticProgress: Double
    let lyricLine: LyricLine?
    let anchorMs: Int
    let anchorDate: Date
    let isPlaying: Bool

    func makeNSView(context: Context) -> KaraokeNSView {
        let view = KaraokeNSView()
        view.apply(
            text: text,
            font: font,
            alignment: alignment,
            staticProgress: staticProgress,
            lyricLine: lyricLine,
            anchorMs: anchorMs,
            anchorDate: anchorDate,
            isPlaying: isPlaying
        )
        return view
    }

    func updateNSView(_ nsView: KaraokeNSView, context: Context) {
        nsView.apply(
            text: text,
            font: font,
            alignment: alignment,
            staticProgress: staticProgress,
            lyricLine: lyricLine,
            anchorMs: anchorMs,
            anchorDate: anchorDate,
            isPlaying: isPlaying
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: KaraokeNSView, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        let width = proposal.width.map { min($0, intrinsic.width) } ?? intrinsic.width
        return CGSize(width: width, height: intrinsic.height)
    }
}

private final class KaraokeNSView: NSView {
    private let baseTextLayer = CATextLayer()
    private let highlightTextLayer = CATextLayer()
    private let maskLayer = CALayer()
    nonisolated(unsafe) private var displayLink: CADisplayLink?

    private var currentText: String = ""
    private var currentFont: NSFont?
    private var currentAlignment: NSTextAlignment = .center
    private var lyricLine: LyricLine?
    private var anchorMs: Int = 0
    private var anchorDate: Date = Date()
    private var isPlaying: Bool = false
    private var staticProgress: Double = 0
    private var lastAppliedProgress: Double = -1

    private static let noImplicit: [String: CAAction] = [
        "bounds": NSNull(),
        "position": NSNull(),
        "contents": NSNull(),
        "frame": NSNull(),
        "string": NSNull(),
        "foregroundColor": NSNull(),
        "hidden": NSNull(),
        "transform": NSNull()
    ]

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        displayLink?.invalidate()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.actions = Self.noImplicit
        layer?.masksToBounds = false

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        baseTextLayer.contentsScale = scale
        baseTextLayer.actions = Self.noImplicit
        baseTextLayer.foregroundColor = NSColor.white.withAlphaComponent(0.42).cgColor
        baseTextLayer.alignmentMode = .center
        baseTextLayer.truncationMode = .none
        baseTextLayer.isWrapped = false
        layer?.addSublayer(baseTextLayer)

        highlightTextLayer.contentsScale = scale
        highlightTextLayer.actions = Self.noImplicit
        highlightTextLayer.foregroundColor = NSColor.white.cgColor
        highlightTextLayer.alignmentMode = .center
        highlightTextLayer.truncationMode = .none
        highlightTextLayer.isWrapped = false
        layer?.addSublayer(highlightTextLayer)

        maskLayer.anchorPoint = .zero
        maskLayer.backgroundColor = NSColor.black.cgColor
        maskLayer.actions = Self.noImplicit
        highlightTextLayer.mask = maskLayer
    }

    override var intrinsicContentSize: NSSize {
        guard !currentText.isEmpty, let font = currentFont else {
            return NSSize(width: NSView.noIntrinsicMetric, height: ceil(currentFont?.boundingRectForFont.height ?? 0))
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (currentText as NSString).size(withAttributes: attrs)
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseTextLayer.frame = bounds
        highlightTextLayer.frame = bounds
        applyProgress(force: true)
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let screen = window?.screen {
            let scale = screen.backingScaleFactor
            baseTextLayer.contentsScale = scale
            highlightTextLayer.contentsScale = scale
        }
        if window != nil {
            startDisplayLinkIfNeeded()
        } else {
            stopDisplayLink()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopDisplayLink()
        }
    }

    func apply(text: String, font: NSFont, alignment: NSTextAlignment, staticProgress: Double, lyricLine: LyricLine?, anchorMs: Int, anchorDate: Date, isPlaying: Bool) {
        var sizeInvalidated = false
        if currentText != text {
            currentText = text
            baseTextLayer.string = text
            highlightTextLayer.string = text
            sizeInvalidated = true
        }
        if currentFont != font {
            currentFont = font
            let ctFont = font as CTFont
            baseTextLayer.font = ctFont
            baseTextLayer.fontSize = font.pointSize
            highlightTextLayer.font = ctFont
            highlightTextLayer.fontSize = font.pointSize
            sizeInvalidated = true
        }
        if currentAlignment != alignment {
            currentAlignment = alignment
            let mode: CATextLayerAlignmentMode
            switch alignment {
            case .center: mode = .center
            case .right: mode = .right
            case .justified: mode = .justified
            case .natural: mode = .natural
            default: mode = .left
            }
            baseTextLayer.alignmentMode = mode
            highlightTextLayer.alignmentMode = mode
        }
        if sizeInvalidated {
            invalidateIntrinsicContentSize()
        }

        let lineChanged = self.lyricLine != lyricLine
        self.lyricLine = lyricLine
        self.anchorMs = anchorMs
        self.anchorDate = anchorDate
        self.isPlaying = isPlaying
        self.staticProgress = staticProgress
        if lineChanged || sizeInvalidated {
            lastAppliedProgress = -1
            applyProgress(force: true)
        }

        if window != nil {
            startDisplayLinkIfNeeded()
        }
    }

    private func currentProgress() -> Double {
        guard isPlaying, let line = lyricLine else {
            return min(1, max(0, staticProgress))
        }
        let elapsedSec = Date().timeIntervalSince(anchorDate)
        let projectedMs = anchorMs + Int(elapsedSec * 1000)
        return min(1, max(0, line.karaokeProgress(at: projectedMs)))
    }

    private func applyProgress(force: Bool = false) {
        let p = currentProgress()
        if !force, abs(p - lastAppliedProgress) < 0.0005 { return }
        lastAppliedProgress = p
        let bounds = highlightTextLayer.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * CGFloat(p), height: bounds.height)
        CATransaction.commit()
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil, isPlaying, lyricLine != nil else {
            if !(isPlaying && lyricLine != nil) { stopDisplayLink() }
            return
        }
        let link = self.displayLink(target: self, selector: #selector(displayLinkFired))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired() {
        applyProgress()
    }
}

private struct CompactArtworkView: View {
    let urlString: String?
    let overlayScale: Double

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString), !urlString.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: CGFloat(40 * overlayScale), height: CGFloat(40 * overlayScale))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: CGFloat(14 * overlayScale), weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.78))
        }
    }
}

private struct NotchSurfaceShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topR = min(topCornerRadius, rect.width / 4, rect.height / 4)
        let bottomR = min(bottomCornerRadius, rect.width / 4, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control: CGPoint(x: rect.minX + topR, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - bottomR))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR + bottomR, y: rect.maxY),
            control: CGPoint(x: rect.minX + topR, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topR - bottomR, y: rect.maxY))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - bottomR),
            control: CGPoint(x: rect.maxX - topR, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topR, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
