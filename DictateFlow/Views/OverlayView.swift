import SwiftUI

struct OverlayView: View {
    let status: AppStatus
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status.iconName)
                .imageScale(.medium)
            Text(message)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(status.bannerColor.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
