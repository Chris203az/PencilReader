import Foundation

/// What the Pencil does in the notebook.
public enum DrawingTool: String, Codable, CaseIterable, Sendable {
    case pen
    case pencil
    case marker
    case eraser
    case lasso

    /// Leaves ink, so it has a color and a width.
    public var isInking: Bool { self == .pen || self == .pencil || self == .marker }

    public var label: String {
        switch self {
        case .pen: "Penna"
        case .pencil: "Matita"
        case .marker: "Evidenziatore"
        case .eraser: "Gomma"
        case .lasso: "Lasso"
        }
    }

    /// The three widths offered in the bar, thin to thick.
    public var widthPresets: [Double] {
        switch self {
        case .pen: [1.5, 3, 6]
        case .pencil: [2, 4, 8]
        case .marker: [12, 20, 30]
        case .eraser, .lasso: []
        }
    }
}

/// An ink color, stored as its components so it can be saved.
public struct InkColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = InkColor(red: 0.1, green: 0.1, blue: 0.1)
    public static let blue = InkColor(red: 0.12, green: 0.36, blue: 0.85)
    public static let red = InkColor(red: 0.84, green: 0.15, blue: 0.24)
    public static let green = InkColor(red: 0.18, green: 0.55, blue: 0.34)
    public static let yellow = InkColor(red: 1, green: 0.85, blue: 0.2)

    /// The five swatches of a new notebook.
    public static let palette: [InkColor] = [.black, .blue, .red, .green, .yellow]
}

/// Color and width of one inking tool.
public struct InkSetting: Codable, Hashable, Sendable {
    public var color: InkColor
    public var width: Double

    public init(color: InkColor, width: Double) {
        self.color = color
        self.width = width
    }
}

/// The tools chosen in the notebook, remembered between sessions.
/// Each inking tool keeps its own color and width.
public struct NotebookToolState: Codable, Equatable, Sendable {
    public private(set) var current: DrawingTool = .pen
    /// The tool before the current one, for the Pencil's "switch to previous" double tap.
    public private(set) var previous: DrawingTool = .eraser
    /// The last pen, pencil or marker used, which the colors and widths apply to.
    public private(set) var lastInking: DrawingTool = .pen
    /// The eraser removes pixels instead of whole strokes.
    public var eraserIsPixel = false
    /// How wide each kind of eraser is; nil until chosen, for the system's own default.
    /// Optional so that tools saved before the eraser had a size still load.
    public var strokeEraserWidth: Double?
    public var pixelEraserWidth: Double?
    public var palette: [InkColor] = InkColor.palette
    public var pen = InkSetting(color: .black, width: 3)
    public var pencil = InkSetting(color: .black, width: 4)
    public var marker = InkSetting(color: .yellow, width: 20)

    public init() {}

    public func ink(for tool: DrawingTool) -> InkSetting? {
        switch tool {
        case .pen: pen
        case .pencil: pencil
        case .marker: marker
        case .eraser, .lasso: nil
        }
    }

    /// The size of the eraser in use, whole strokes or pixels; nil for the system's default.
    public var eraserWidth: Double? {
        eraserIsPixel ? pixelEraserWidth : strokeEraserWidth
    }

    /// Sets the size of the kind of eraser in use, and takes the eraser.
    public mutating func setEraserWidth(_ width: Double) {
        if eraserIsPixel { pixelEraserWidth = width } else { strokeEraserWidth = width }
        select(.eraser)
    }

    public mutating func select(_ tool: DrawingTool) {
        guard tool != current else { return }
        previous = current
        current = tool
        if tool.isInking { lastInking = tool }
    }

    /// Applies to the pen, pencil or marker last used, and picks it up again if another tool was in hand.
    public mutating func setColor(_ color: InkColor) {
        update { $0.color = color }
        select(lastInking)
    }

    public mutating func setWidth(_ width: Double) {
        update { $0.width = width }
        select(lastInking)
    }

    /// The double tap on Apple Pencil 2: to the eraser and back, or to the previous tool,
    /// as chosen in the system settings.
    public mutating func pencilDoubleTap(switchesToEraser: Bool) {
        if switchesToEraser {
            select(current == .eraser ? lastInking : .eraser)
        } else {
            select(previous)
        }
    }

    private mutating func update(_ change: (inout InkSetting) -> Void) {
        switch lastInking {
        case .pen: change(&pen)
        case .pencil: change(&pencil)
        case .marker: change(&marker)
        case .eraser, .lasso: break
        }
    }
}

/// The controls of the notebook's tool bar, each of which can be shown or hidden and moved.
public enum NotebookToolbarItem: String, Codable, CaseIterable, Sendable {
    case pen
    case pencil
    case marker
    case eraser
    case lasso
    case ruler
    case colors
    case width
    case undo
    case redo
    case shapes
    case paper

    public var label: String {
        switch self {
        case .pen: "Penna"
        case .pencil: "Matita"
        case .marker: "Evidenziatore"
        case .eraser: "Gomma"
        case .lasso: "Lasso"
        case .ruler: "Righello"
        case .colors: "Colori"
        case .width: "Spessore"
        case .undo: "Annulla"
        case .redo: "Ripristina"
        case .shapes: "Forme automatiche"
        case .paper: "Sfondo"
        }
    }
}

/// Where the tool bar sits and what it shows, in which order.
public struct NotebookToolbarLayout: Codable, Equatable, Sendable {
    public enum Position: String, Codable, CaseIterable, Sendable {
        case top
        case bottom

        public var label: String { self == .top ? "In alto" : "In basso" }
    }

    public struct Entry: Codable, Equatable, Hashable, Sendable {
        public var item: NotebookToolbarItem
        public var isVisible: Bool

        public init(item: NotebookToolbarItem, isVisible: Bool) {
            self.item = item
            self.isVisible = isVisible
        }
    }

    public var position: Position
    public var entries: [Entry]

    public init(position: Position = .top, entries: [Entry]) {
        self.position = position
        self.entries = entries
    }

    /// At the top, everything shown, in the order of `NotebookToolbarItem`.
    public static let standard = NotebookToolbarLayout(
        entries: NotebookToolbarItem.allCases.map { Entry(item: $0, isVisible: true) })

    public var visibleItems: [NotebookToolbarItem] { entries.filter(\.isVisible).map(\.item) }

    /// Each item once: duplicates go, and items added in a later version appear at the end, shown.
    public func normalized() -> NotebookToolbarLayout {
        var seen: Set<NotebookToolbarItem> = []
        var fixed = entries.filter { seen.insert($0.item).inserted }
        for item in NotebookToolbarItem.allCases where !seen.contains(item) {
            fixed.append(Entry(item: item, isVisible: true))
        }
        return NotebookToolbarLayout(position: position, entries: fixed)
    }
}
