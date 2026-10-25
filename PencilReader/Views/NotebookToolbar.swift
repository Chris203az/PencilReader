import Observation
import PencilKit
import ReaderCore
import SwiftUI

/// The tool in hand and how the notebook's tool bar is laid out, saved between sessions.
@MainActor
@Observable
final class NotebookTools {
    private(set) var state: NotebookToolState {
        didSet { Self.save(state, forKey: Self.stateKey) }
    }
    var layout: NotebookToolbarLayout {
        didSet { Self.save(layout, forKey: Self.layoutKey) }
    }
    /// Not saved: the ruler is put away when the notebook closes.
    var isRulerActive = false

    private static let stateKey = "notebookTools"
    private static let layoutKey = "notebookToolbar"

    init() {
        state = Self.load(NotebookToolState.self, forKey: Self.stateKey) ?? NotebookToolState()
        layout = (Self.load(NotebookToolbarLayout.self, forKey: Self.layoutKey) ?? .standard).normalized()
    }

    func select(_ tool: DrawingTool) { state.select(tool) }
    func setColor(_ color: InkColor) { state.setColor(color) }
    func setWidth(_ width: Double) { state.setWidth(width) }

    /// Changes a swatch, and inks with it.
    func setPaletteColor(_ color: InkColor, at index: Int) {
        guard state.palette.indices.contains(index) else { return }
        state.palette[index] = color
        state.setColor(color)
    }

    /// Color and width the swatches and the width buttons show: those of the last pen, pencil or marker.
    var currentInk: InkSetting? { state.ink(for: state.lastInking) }

    /// Follows the double-tap choice in Settings > Apple Pencil.
    func pencilDoubleTap() {
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser: state.pencilDoubleTap(switchesToEraser: true)
        case .switchPrevious: state.pencilDoubleTap(switchesToEraser: false)
        default: break
        }
    }

    var pkTool: PKTool {
        let tool = state.current
        switch tool {
        case .pen, .pencil, .marker:
            let ink = state.ink(for: tool) ?? InkSetting(color: .black, width: 3)
            return PKInkingTool(tool.inkType, color: ink.color.uiColor, width: ink.width)
        case .eraser:
            return PKEraserTool(state.eraserIsPixel ? .bitmap : .vector)
        case .lasso:
            // The notebook draws its own lasso (LassoEditor) and turns PencilKit's drawing off
            // meanwhile; PencilKit's lasso, which can only move strokes, is never used.
            let ink = state.ink(for: state.lastInking) ?? InkSetting(color: .black, width: 3)
            return PKInkingTool(state.lastInking.inkType, color: ink.color.uiColor, width: ink.width)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

extension DrawingTool {
    var inkType: PKInkingTool.InkType {
        switch self {
        case .pencil: .pencil
        case .marker: .marker
        default: .pen
        }
    }

    /// Widths the slider offers.
    var widthRange: ClosedRange<Double> {
        switch self {
        case .pencil: 1...16
        case .marker: 5...40
        default: 0.5...12
        }
    }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        case .marker: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }
}

extension InkColor {
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

/// The notebook's own tool bar, fixed at the top or the bottom of the pane, with the controls
/// chosen in its settings, in their order. Scrolls sideways when they do not all fit.
struct NotebookToolbar: View {
    @Bindable var notebook: NotebookModel

    private var tools: NotebookTools { notebook.tools }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tools.layout.visibleItems, id: \.self) { item in
                    control(for: item)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 44)
        .background(.bar)
    }

    @ViewBuilder private func control(for item: NotebookToolbarItem) -> some View {
        switch item {
        case .pen: toolButton(.pen)
        case .pencil: toolButton(.pencil)
        case .marker: toolButton(.marker)
        case .eraser: toolButton(.eraser, symbol: tools.state.eraserIsPixel ? "eraser.line.dashed" : "eraser")
        case .lasso: toolButton(.lasso)
        case .ruler:
            barButton("Righello", symbol: "ruler", isActive: tools.isRulerActive) { tools.isRulerActive.toggle() }
        case .colors:
            HStack(spacing: 6) {
                ForEach(tools.state.palette.indices, id: \.self) { index in
                    ColorSwatch(tools: tools, index: index)
                }
            }
            .padding(.horizontal, 6)
        case .width:
            WidthButtons(tools: tools)
        case .undo:
            barButton("Annulla", symbol: "arrow.uturn.backward") { notebook.undo() }
        case .redo:
            barButton("Ripristina", symbol: "arrow.uturn.forward") { notebook.redo() }
        case .shapes:
            barButton("Forme automatiche", symbol: "square.on.circle", isActive: notebook.straightensShapes) {
                notebook.straightensShapes.toggle()
            }
        case .paper:
            Menu {
                Picker("Sfondo", selection: $notebook.paper) {
                    ForEach(PaperStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
            } label: {
                BarIcon(symbol: "square.grid.3x3", isActive: false)
            }
            .accessibilityLabel("Sfondo")
        }
    }

    /// Tapping the eraser while it is in hand switches between whole strokes and pixels.
    private func toolButton(_ tool: DrawingTool, symbol: String? = nil) -> some View {
        barButton(tool.label, symbol: symbol ?? tool.symbol, isActive: tools.state.current == tool) {
            tools.select(tool)
        }
    }

    private func barButton(_ title: String, symbol: String, isActive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BarIcon(symbol: symbol, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// One control of the bar; the tool in hand is tinted.
private struct BarIcon: View {
    let symbol: String
    let isActive: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18))
            .frame(width: 36, height: 34)
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .background(isActive ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}

/// A preset color: a tap inks with it, holding it changes it.
private struct ColorSwatch: View {
    let tools: NotebookTools
    let index: Int
    @State private var isEditing = false

    private var color: InkColor { tools.state.palette[index] }
    private var isSelected: Bool { tools.state.current.isInking && tools.currentInk?.color == color }

    var body: some View {
        Circle()
            .fill(Color(uiColor: color.uiColor))
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
            .padding(3)
            .overlay {
                if isSelected { Circle().stroke(Color.accentColor, lineWidth: 2) }
            }
            .contentShape(Circle())
            .onTapGesture { tools.setColor(color) }
            .onLongPressGesture(minimumDuration: 0.4) { isEditing = true }
            .popover(isPresented: $isEditing) {
                ColorPicker("Colore del campione", selection: Binding(
                    get: { Color(uiColor: color.uiColor) },
                    set: { tools.setPaletteColor(InkColor($0), at: index) }
                ), supportsOpacity: false)
                .padding()
                .frame(width: 300)
            }
            .accessibilityLabel("Colore \(index + 1)")
            .accessibilityHint("Tieni premuto per cambiarlo")
    }
}

/// Three preset widths for the pen, pencil or marker in use, and a slider for any other.
private struct WidthButtons: View {
    let tools: NotebookTools
    @State private var showsSlider = false

    private var tool: DrawingTool { tools.state.lastInking }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(tool.widthPresets.enumerated()), id: \.offset) { step, width in
                Button {
                    tools.setWidth(width)
                } label: {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 5 + CGFloat(step) * 5, height: 5 + CGFloat(step) * 5)
                        .frame(width: 30, height: 34)
                        .background(tools.currentInk?.width == width ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Spessore \(step + 1)")
            }
            Button {
                showsSlider = true
            } label: {
                BarIcon(symbol: "slider.horizontal.below.rectangle", isActive: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Altro spessore")
            .popover(isPresented: $showsSlider) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Spessore \(tool.label.lowercased())")
                        .font(.headline)
                    Slider(value: Binding(get: { tools.currentInk?.width ?? tool.widthRange.lowerBound },
                                          set: { tools.setWidth($0) }),
                           in: tool.widthRange)
                    Text((tools.currentInk?.width ?? 0).formatted(.number.precision(.fractionLength(1))) + " pt")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding()
                .frame(width: 300)
            }
        }
    }
}

/// Where the tool bar sits and which controls it shows, in which order.
struct ToolbarSettingsView: View {
    @Bindable var tools: NotebookTools
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Posizione", selection: $tools.layout.position) {
                        ForEach(NotebookToolbarLayout.Position.allCases, id: \.self) { position in
                            Text(position.label).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Posizione")
                }
                Section {
                    ForEach($tools.layout.entries, id: \.item) { $entry in
                        Toggle(entry.item.label, isOn: $entry.isVisible)
                    }
                    .onMove { tools.layout.entries.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Elementi")
                } footer: {
                    Text("Trascina per cambiare l'ordine.")
                }
                Section {
                    Button("Ripristina predefiniti") { tools.layout = .standard }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Barra strumenti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}
