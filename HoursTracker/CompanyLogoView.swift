import SwiftUI

struct CompanyLogoView: View {
    var size: CGFloat = 38
    var width: CGFloat? = nil
    var cornerRadius: CGFloat? = nil

    private var computedWidth: CGFloat {
        width ?? size
    }

    private var computedCornerRadius: CGFloat {
        cornerRadius ?? (size * 0.26)
    }

    private var iconSize: CGFloat {
        size * 0.47
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.card2
            Image(systemName: "building.2.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(AppTheme.Colors.brand)
        }
        .frame(width: computedWidth, height: size)
        .clipShape(RoundedRectangle(cornerRadius: computedCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: computedCornerRadius, style: .continuous)
                .stroke(AppTheme.Colors.stroke, lineWidth: 1)
        )
    }
}
