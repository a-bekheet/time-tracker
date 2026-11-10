import SwiftUI

extension Color {
    static let trackerBlue = Color(red: 0.06, green: 0.36, blue: 0.79)
}

extension View {
    func trackerSurface(tint: Color? = nil) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: 18)
            shape.fill(.quaternary.opacity(0.45))
                .overlay { shape.fill(tint?.opacity(0.08) ?? .clear) }
        }
    }

    @ViewBuilder func trackerButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) }
            else { buttonStyle(.bordered) }
        }
    }
}

struct TrackerBadge: View {
    let symbol: String
    var color: Color = .accentColor
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.29))
            .accessibilityHidden(true)
    }
}
