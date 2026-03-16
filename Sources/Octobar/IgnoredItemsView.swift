import SwiftUI

struct IgnoredItemsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openURL) private var openURL

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        Group {
            if model.ignoredItems.isEmpty {
                ContentUnavailableView {
                    Label("No ignored items", systemImage: "eye.slash")
                } description: {
                    Text("Ignored pull requests and issues will appear here so you can restore them later.")
                }
            } else {
                List {
                    ForEach(model.ignoredItems) { ignoredItem in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ignoredItem.title)
                                    .font(.headline)

                                Text(ignoredItem.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text("Ignored \(ignoredRelativeTimestamp(for: ignoredItem))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 20)

                            HStack(spacing: 10) {
                                Button("Open") {
                                    openURL(ignoredItem.url)
                                }
                                .buttonStyle(.bordered)
                                .appInteractiveHover()

                                Button("Restore") {
                                    model.unignore(ignoredItem)
                                }
                                .buttonStyle(.borderedProminent)
                                .appInteractiveHover()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }

    private func ignoredRelativeTimestamp(for ignoredItem: IgnoredAttentionSubject) -> String {
        relativeFormatter.localizedString(for: ignoredItem.ignoredAt, relativeTo: Date())
    }
}
