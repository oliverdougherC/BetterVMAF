import SwiftUI

/// A native button with explicit accessible state and an in-bounds full-row target.
struct ReviewDisclosure<Content: View>: View {
    let title: String
    private let externalExpansion: Binding<Bool>?
    private let content: Content
    @State private var localExpansion = false

    init(_ title: String, isExpanded: Binding<Bool>? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.externalExpansion = isExpanded
        self.content = content()
    }

    var body: some View {
        let expanded = externalExpansion?.wrappedValue ?? localExpansion
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if let externalExpansion { externalExpansion.wrappedValue.toggle() }
                else { localExpansion.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption).frame(width: 12).accessibilityHidden(true)
                    Text(title)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded { content.padding(.leading, 20) }
        }
    }
}
