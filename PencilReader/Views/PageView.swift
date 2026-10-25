import ReaderCore
import SwiftUI

/// One page: the image, the recognized-word overlay, the Pencil layer and the translation panel.
/// In study mode the Pencil marks the page and the study tools float over its bottom.
struct PageView: View {
    let model: ReaderModel
    var study: StudyModel?
    let onExit: () -> Void
    @State private var panelHeight: CGFloat = 220
    /// 1 = page fitted to the screen.
    @State private var zoom: CGFloat = 1
    /// Distance of the zoomed page's center from the fitted page's center.
    @State private var offset: CGSize = .zero

    private let panelWidth: CGFloat = 380
    private let margin: CGFloat = 12
    private let maxZoom: CGFloat = 5
    private let doubleTapZoom: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            if let image = model.pageImage {
                let base = fit(image.size, in: CGRect(origin: .zero, size: geo.size).insetBy(dx: margin, dy: margin))
                let frame = zoomed(base, zoom: zoom, offset: offset, in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                        .offset(x: frame.minX, y: frame.minY)

                    WordBoxes(pageText: model.pageText,
                              frame: frame,
                              showAll: model.showWordBoxes,
                              selected: Set(model.selection?.wordIDs ?? []),
                              found: model.searchHighlightOnPage)
                        .allowsHitTesting(false)

                    LassoCanvas(allowsFinger: model.allowsFingerDrawing && !isStudying,
                                isZoomed: zoom > 1,
                                onStroke: { model.select(stroke: $0, imageFrame: frame) },
                                onTap: { model.clearSelection() },
                                onSwipe: { direction in
                                    switch direction {
                                    case .left: model.nextPage()
                                    case .right: model.previousPage()
                                    case .down: onExit()
                                    default: break
                                    }
                                },
                                onZoom: { scale, center in
                                    zoom(by: scale, around: center, base: base, size: geo.size)
                                },
                                onZoomEnded: {
                                    if zoom < 1.05 { withAnimation(.snappy) { resetZoom() } }
                                },
                                onPan: { delta in
                                    let current = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
                                    store(zoomed(base, zoom: zoom, offset: current, in: geo.size), base: base)
                                },
                                onDoubleTap: { point in
                                    withAnimation(.snappy) {
                                        if zoom > 1 {
                                            resetZoom()
                                        } else {
                                            zoom(by: doubleTapZoom, around: point, base: base, size: geo.size)
                                        }
                                    }
                                },
                                study: isStudying ? study.map { ($0, model.pageIndex, frame, model.pageText) } : nil)

                    if let selection = model.selection {
                        TranslationPanel(selection: selection, onClose: model.clearSelection)
                            .frame(width: panelWidth)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { panelHeight = $0 }
                            .position(panelCenter(for: selection.anchor.denormalized(in: frame), in: geo.size))
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    if isStudying, let study {
                        StudyToolbar(study: study)
                            .frame(maxWidth: geo.size.width - 2 * margin)
                            .position(x: geo.size.width / 2, y: geo.size.height - 44)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if model.isRecognizing {
                        Label("Riconoscimento testo…", systemImage: "text.viewfinder")
                            .font(.callout)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .position(x: geo.size.width / 2, y: 28)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.snappy(duration: 0.2), value: model.selection?.id)
                .animation(.snappy(duration: 0.25), value: isStudying)
            }
        }
        .clipped()
        .background(Color(.secondarySystemBackground))
        .onChange(of: model.pageIndex) { resetZoom() }
    }

    private var isStudying: Bool { study?.isActive == true }

    // MARK: Zoom

    private func resetZoom() {
        zoom = 1
        offset = .zero
    }

    /// Scales the page keeping `center` (a point on screen) still.
    private func zoom(by scale: CGFloat, around center: CGPoint, base: CGRect, size: CGSize) {
        let current = zoomed(base, zoom: zoom, offset: offset, in: size)
        let s = min(max(zoom * scale, 1), maxZoom) / zoom
        let scaled = CGRect(x: center.x - (center.x - current.minX) * s,
                            y: center.y - (center.y - current.minY) * s,
                            width: current.width * s, height: current.height * s)
        let newZoom = scaled.width / base.width
        let newOffset = CGSize(width: scaled.midX - base.midX, height: scaled.midY - base.midY)
        store(zoomed(base, zoom: newZoom, offset: newOffset, in: size), base: base)
    }

    private func store(_ frame: CGRect, base: CGRect) {
        zoom = frame.width / base.width
        offset = CGSize(width: frame.midX - base.midX, height: frame.midY - base.midY)
    }

    /// The page on screen; its edges never come inside the screen margins,
    /// and it stays centered along a side where it is smaller than the screen.
    private func zoomed(_ base: CGRect, zoom: CGFloat, offset: CGSize, in size: CGSize) -> CGRect {
        guard zoom > 1 else { return base }
        let w = base.width * zoom, h = base.height * zoom
        func clamp(_ origin: CGFloat, _ length: CGFloat, _ available: CGFloat) -> CGFloat {
            let inner = available - 2 * margin
            if length <= inner { return margin + (inner - length) / 2 }
            return min(margin, max(available - margin - length, origin))
        }
        return CGRect(x: clamp(base.midX - w / 2 + offset.width, w, size.width),
                      y: clamp(base.midY - h / 2 + offset.height, h, size.height),
                      width: w, height: h)
    }

    /// Below the lasso if it fits, otherwise above; always on screen.
    private func panelCenter(for anchor: CGRect, in size: CGSize) -> CGPoint {
        let half = panelWidth / 2
        let x = min(max(anchor.midX, half + margin), size.width - half - margin)
        let below = anchor.maxY + 16 + panelHeight / 2
        let above = anchor.minY - 16 - panelHeight / 2
        let y: CGFloat
        if below + panelHeight / 2 <= size.height - margin {
            y = below
        } else if above - panelHeight / 2 >= margin {
            y = above
        } else {
            y = size.height - margin - panelHeight / 2
        }
        return CGPoint(x: x, y: y)
    }

    private func fit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

/// Highlights selected words and search results; in debug mode also outlines every recognized word.
private struct WordBoxes: View {
    let pageText: PageText?
    let frame: CGRect
    let showAll: Bool
    let selected: Set<Int>
    /// Words of the search result the page was opened from.
    let found: Set<Int>

    var body: some View {
        Canvas { context, _ in
            guard let pageText else { return }
            for word in pageText.words {
                let rect = word.rect.denormalized(in: frame)
                if found.contains(word.id) {
                    context.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: -1), cornerRadius: 3),
                                 with: .color(.orange.opacity(0.35)))
                }
                if selected.contains(word.id) {
                    context.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: -1), cornerRadius: 3),
                                 with: .color(.yellow.opacity(0.4)))
                }
                if showAll {
                    context.stroke(Path(rect), with: .color(.green.opacity(0.8)), lineWidth: 0.75)
                }
            }
        }
    }
}
