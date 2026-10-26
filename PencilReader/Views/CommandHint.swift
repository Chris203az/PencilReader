import SwiftUI

/// A bar button that, held down, shows a short description of what it does instead of doing it.
struct HintButton<Label: View>: View {
    let hint: String
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var showsHint = false
    /// Set once the press became a hold, so lifting the finger does not run the action too.
    @State private var swallowsTap = false

    var body: some View {
        Button {
            if swallowsTap {
                swallowsTap = false
            } else {
                action()
            }
        } label: {
            label
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            swallowsTap = true
            showsHint = true
        })
        .popover(isPresented: $showsHint) {
            Text(hint)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280, alignment: .leading)
                .padding()
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: showsHint) { _, shown in
            // A hold that ended off the button never reached the action: the next tap must work.
            if !shown { swallowsTap = false }
        }
        // Goes away by itself; a tap anywhere closes it sooner.
        .task(id: showsHint) {
            guard showsHint else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            showsHint = false
        }
    }
}

extension HintButton where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, systemImage: String, hint: String, action: @escaping () -> Void) {
        self.init(hint: hint, action: action) { SwiftUI.Label(title, systemImage: systemImage) }
    }
}
