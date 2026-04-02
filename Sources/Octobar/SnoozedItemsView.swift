import SwiftUI

struct SnoozedItemsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openURL) private var openURL

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private let untilFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Group {
            if model.snoozedItems.isEmpty {
                ContentUnavailableView {
                    Label("No snoozed items", systemImage: "moon.zzz")
                } description: {
                    Text("Snoozed pull requests and issues will appear here so you can restore them before their timer ends.")
                }
            } else {
                List {
                    ForEach(model.snoozedItems) { snoozedItem in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snoozedItem.title)
                                    .font(.headline)

                                Text(snoozedItem.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text("Until \(untilFormatter.string(from: snoozedItem.snoozedUntil))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("Snoozed \(relativeFormatter.localizedString(for: snoozedItem.snoozedAt, relativeTo: Date()))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 20)

                            HStack(spacing: 10) {
                                Button("Open") {
                                    openURL(snoozedItem.url)
                                }
                                .buttonStyle(.bordered)
                                .appInteractiveHover()

                                Button("Restore") {
                                    model.unsnooze(snoozedItem)
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
}
