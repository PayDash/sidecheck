import SwiftUI

/// The clipboard history app: searchable list of everything copied on the
/// system. Tapping a row re-copies it; rows show a checkmark flash and delete
/// on hover.
struct ClipboardAppView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var clipboard: ClipboardStore
    @State private var query = ""

    private var filtered: [ClipboardStore.Item] {
        query.isEmpty
            ? clipboard.items
            : clipboard.items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 10) {
            searchField

            HStack(spacing: 8) {
                Text("\(clipboard.items.count) item\(clipboard.items.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                if !clipboard.items.isEmpty {
                    Button {
                        clipboard.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.cardFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Clear clipboard history")
                }
            }

            if clipboard.items.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                Text("No copies match “\(query)”")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { item in
                            ClipboardRow(item: item)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    // MARK: pieces

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            TextField("Search copies", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.cardStroke, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(theme.textTertiary)
                .themeGlow(theme)
            Text("Nothing copied yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Text("Everything you copy lands here automatically")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One history row: tap to re-copy, hover to reveal delete.
private struct ClipboardRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var clipboard: ClipboardStore
    let item: ClipboardStore.Item
    @State private var hovered = false

    private var isLink: Bool {
        let lowered = item.text.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
    }

    private var isFlashing: Bool { clipboard.flashID == item.id }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                clipboard.recopy(item)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)

            if hovered {
                Button {
                    clipboard.remove(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .padding(6)
                        .background(Circle().fill(theme.cardFill))
                        .overlay(Circle().strokeBorder(theme.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .help("Remove from history")
            }
        }
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovered)
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Image(systemName: isLink ? "link" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.accent)
                .themeGlow(theme)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.date, format: .relative(presentation: .named))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer(minLength: 0)

            if isFlashing {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isFlashing ? theme.accent.opacity(0.14) : theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isFlashing ? theme.accent.opacity(0.5) : theme.cardStroke, lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFlashing)
    }
}
