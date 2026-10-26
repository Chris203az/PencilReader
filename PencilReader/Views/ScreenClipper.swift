import ReaderCore
import UIKit
import UniformTypeIdentifiers

/// Cuts a part of the screen out with the Pencil and copies it to the clipboard as a PNG.
/// Nothing is saved to Photos.
///
/// The whole window is covered by a frozen snapshot of itself, so the reader under it gets
/// no touches while clipping: lasso, translation, study marks and notebook stay as they were.
@MainActor
enum ScreenClipper {
    static func start() {
        guard let window = keyWindow, !window.subviews.contains(where: { $0 is ScreenClipView }) else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.traitCollection.displayScale
        format.opaque = true
        let snapshot = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        let view = ScreenClipView(snapshot: snapshot)
        view.frame = window.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(view)
        view.appear()
    }

    /// The snapshot inside `clip`'s rectangle, at the screen's own scale.
    static func image(of clip: ScreenClip, from snapshot: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: clip.rect.size, format: format).image { _ in
            snapshot.draw(at: CGPoint(x: -clip.rect.minX, y: -clip.rect.minY))
        }
    }

    /// As PNG: lossless, so text in the copy stays sharp.
    static func copy(_ image: UIImage) -> Bool {
        guard let png = image.pngData() else { return false }
        UIPasteboard.general.setItems([[UTType.png.identifier: png]])
        return true
    }

    private static var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
}

/// The clipping mode: the frozen screen, a hint with Annulla, the stroke being drawn
/// and the rectangle that will be copied, reaching the stroke's farthest points.
/// Only the Pencil draws; a finger tap leaves without copying.
private final class ScreenClipView: UIView {
    private let snapshot: UIImage
    private let snapshotView: UIImageView
    private let dim = UIView()
    private let strokeLayer = CAShapeLayer()
    private let rectLayer = CAShapeLayer()
    private let hint = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let hintLabel = UILabel()
    private var points: [CGPoint] = []
    private var pencil: UITouch?
    private var fingerStart: (location: CGPoint, time: TimeInterval)?
    private var finished = false

    private static let hintText = "Disegna con la Pencil intorno alla parte da copiare"

    init(snapshot: UIImage) {
        self.snapshot = snapshot
        snapshotView = UIImageView(image: snapshot)
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .black

        snapshotView.frame = bounds
        snapshotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(snapshotView)

        dim.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        dim.frame = bounds
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.isUserInteractionEnabled = false
        addSubview(dim)

        rectLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
        rectLayer.strokeColor = UIColor.systemBlue.cgColor
        rectLayer.lineWidth = 2
        rectLayer.lineDashPattern = [8, 5]
        layer.addSublayer(rectLayer)

        strokeLayer.fillColor = nil
        strokeLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        strokeLayer.lineWidth = 2
        strokeLayer.lineJoin = .round
        strokeLayer.lineCap = .round
        layer.addSublayer(strokeLayer)

        setUpHint()
        accessibilityViewIsModal = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUpHint() {
        hintLabel.text = Self.hintText
        hintLabel.font = .preferredFont(forTextStyle: .callout)
        hintLabel.numberOfLines = 2

        var cancel = UIButton.Configuration.borderedTinted()
        cancel.title = "Annulla"
        cancel.cornerStyle = .capsule
        let cancelButton = UIButton(configuration: cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss()
        })

        let icon = UIImageView(image: UIImage(systemName: "scissors"))
        icon.tintColor = .secondaryLabel
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [icon, hintLabel, cancelButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        hint.clipsToBounds = true
        hint.layer.cornerRadius = 24
        hint.layer.cornerCurve = .continuous
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.contentView.addSubview(row)
        addSubview(hint)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: hint.contentView.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: hint.contentView.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: hint.contentView.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: hint.contentView.bottomAnchor, constant: -8),
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            hint.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
        ])
    }

    func appear() {
        dim.alpha = 0
        hint.alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.dim.alpha = 1
            self.hint.alpha = 1
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Rotated or resized: the snapshot no longer matches the screen.
        if !finished, bounds.size != snapshot.size { dismiss() }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !finished else { return }
        for touch in touches {
            if touch.type == .pencil {
                guard pencil == nil else { continue }
                pencil = touch
                fingerStart = nil
                points = [touch.location(in: self)]
                hintLabel.text = Self.hintText
                updateOutline()
            } else if pencil == nil, touches.count == 1, event?.allTouches?.count == 1 {
                fingerStart = (touch.location(in: self), touch.timestamp)
            } else {
                fingerStart = nil
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pencil, touches.contains(pencil) {
            points += (event?.coalescedTouches(for: pencil) ?? [pencil]).map { $0.location(in: self) }
            updateOutline()
        }
        if let start = fingerStart, let finger = touches.first(where: { $0.type != .pencil }),
           hypot(finger.location(in: self).x - start.location.x, finger.location(in: self).y - start.location.y) > 12 {
            fingerStart = nil
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pencil, touches.contains(pencil) {
            points += (event?.coalescedTouches(for: pencil) ?? [pencil]).map { $0.location(in: self) }
            self.pencil = nil
            finishStroke()
            return
        }
        // A short, still finger tap leaves; a resting palm is neither.
        if let start = fingerStart, let finger = touches.first(where: { $0.type != .pencil }),
           finger.timestamp - start.time < 0.4 {
            fingerStart = nil
            dismiss()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pencil, touches.contains(pencil) {
            self.pencil = nil
            points = []
            updateOutline()
        }
        fingerStart = nil
    }

    private func updateOutline() {
        guard let first = points.first else {
            strokeLayer.path = nil
            rectLayer.path = nil
            return
        }
        let path = UIBezierPath()
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        strokeLayer.path = path.cgPath
        rectLayer.path = UIBezierPath(rect: CGRect(boundingPoints: points)).cgPath
    }

    // MARK: Result

    private func finishStroke() {
        guard let clip = ScreenClip.make(stroke: points, bounds: bounds, scale: snapshot.scale) else {
            // A slip or a too small loop: stay, and say how to do it.
            points = []
            updateOutline()
            hintLabel.text = "Disegna un contorno più grande, oppure Annulla"
            return
        }
        let image = ScreenClipper.image(of: clip, from: snapshot)
        guard ScreenClipper.copy(image) else {
            hintLabel.text = "Non sono riuscito a copiare, riprova"
            points = []
            updateOutline()
            return
        }
        UIImpactFeedbackGenerator(style: .light, view: self).impactOccurred()
        showCopied(image, clip: clip)
    }

    /// Flash on the cut part, the frozen screen fades away, a small preview says it was copied.
    private func showCopied(_ image: UIImage, clip: ScreenClip) {
        finished = true
        isUserInteractionEnabled = false
        strokeLayer.path = nil
        rectLayer.path = nil

        let flash = UIImageView(image: image)
        flash.frame = clip.rect
        flash.contentMode = .scaleAspectFit
        addSubview(flash)
        let white = UIView(frame: flash.bounds)
        white.backgroundColor = UIColor.white.withAlphaComponent(0.7)
        white.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        flash.addSubview(white)

        let (toast, thumbFrame) = copiedToast(image)
        toast.alpha = 0
        addSubview(toast)

        UIView.animate(withDuration: 0.25) {
            white.alpha = 0
            self.hint.alpha = 0
            self.dim.alpha = 0
        }
        UIView.animate(withDuration: 0.35, delay: 0.15, options: .curveEaseInOut) {
            self.snapshotView.alpha = 0
            self.backgroundColor = .clear
            flash.frame = thumbFrame
            flash.alpha = 0
            toast.alpha = 1
        } completion: { _ in
            flash.removeFromSuperview()
            UIView.animate(withDuration: 0.3, delay: 1.2) {
                toast.alpha = 0
            } completion: { _ in
                self.removeFromSuperview()
            }
        }
    }

    /// The toast, and where its thumbnail sits in this view.
    private func copiedToast(_ image: UIImage) -> (UIView, CGRect) {
        let side: CGFloat = 56
        let ratio = image.size.width / max(image.size.height, 1)
        let thumbSize = ratio >= 1 ? CGSize(width: min(side * ratio, side * 2), height: side)
                                   : CGSize(width: max(side * ratio, 20), height: side)

        let toast = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        toast.clipsToBounds = true
        toast.layer.cornerRadius = 18
        toast.layer.cornerCurve = .continuous

        let thumb = UIImageView(image: image)
        thumb.contentMode = .scaleAspectFit
        thumb.frame = CGRect(origin: CGPoint(x: 10, y: 10), size: thumbSize)
        let label = UILabel()
        label.text = "Copiato negli appunti"
        label.font = .preferredFont(forTextStyle: .headline)
        label.sizeToFit()
        label.frame.origin = CGPoint(x: thumb.frame.maxX + 12, y: (side + 20 - label.frame.height) / 2)

        toast.contentView.addSubview(thumb)
        toast.contentView.addSubview(label)
        let size = CGSize(width: label.frame.maxX + 18, height: side + 20)
        toast.frame = CGRect(x: (bounds.width - size.width) / 2, y: safeAreaInsets.top + 8,
                             width: size.width, height: size.height)
        return (toast, thumb.frame.offsetBy(dx: toast.frame.minX, dy: toast.frame.minY))
    }

    // MARK: Leaving

    private func dismiss() {
        guard !finished else { return }
        finished = true
        isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.2) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
}
