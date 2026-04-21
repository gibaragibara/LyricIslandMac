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

            KaraokeLineText(text: model.currentLine, progress: model.currentProgress, alignment: .center)
                .font(.system(size: scaled(15), weight: .semibold))
                .lineLimit(1)
                .animation(.linear(duration: 0.08), value: model.currentProgress)

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

    private var compactContent: some View {
        HStack(spacing: 12) {
            compactLeadingBadge

            VStack(alignment: .center, spacing: 2) {
                KaraokeLineText(text: model.compactPrimaryLine, progress: model.currentProgress, alignment: .center)
                    .font(.system(size: scaled(16), weight: .semibold))
                    .lineLimit(1)
                    .animation(.linear(duration: 0.08), value: model.currentProgress)

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
        NotchSurfaceShape(
            topCornerRadius: (model.isExpanded ? 22 : 10) * model.overlayScale,
            bottomCornerRadius: (model.isExpanded ? 36 : 999) * model.overlayScale
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
    var alignment: Alignment = .leading

    var body: some View {
        let clampedProgress = min(1, max(0, progress))
        ZStack(alignment: alignment) {
            Text(text)
                .foregroundStyle(Color.white.opacity(0.42))

            Text(text)
                .foregroundStyle(Color.white)
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(width: proxy.size.width * clampedProgress)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
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
