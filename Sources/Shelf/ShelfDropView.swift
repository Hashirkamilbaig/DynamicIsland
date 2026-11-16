import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfDropView: View {
    @ObservedObject var store: ShelfStore
    var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.items.isEmpty {
                Text(isExpanded ? "Drop files here (kept 20s)" : "Drop")
                    .font(.system(size: isExpanded ? 12 : 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: isExpanded ? 44 : 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.items) { item in
                            ShelfItemChip(item: item, store: store)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, isExpanded ? 4 : 0)
        // Parent IslandView owns drop targeting (so a drag can expand the tucked island).
        // Keep a secondary drop zone here for drops onto the shelf chrome once revealed.
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let error {
                        Log.shelf.error("Drop load error: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let urlItem = item as? URL {
                        url = urlItem
                    } else if let string = item as? String {
                        url = URL(string: string)
                    } else {
                        url = nil
                    }
                    guard let url else { return }
                    Task { @MainActor in
                        store.ingest(url: url)
                    }
                }
            }
        }
        return accepted
    }
}

private struct ShelfItemChip: View {
    let item: ShelfItem
    @ObservedObject var store: ShelfStore

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
            Text(item.originalName)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .frame(width: 72)
            Text("\(Int(item.remainingSeconds.rounded(.up)))s")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onDrag {
            NSItemProvider(contentsOf: item.cachedURL) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Remove") { store.remove(item) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.cachedURL])
            }
        }
        .help("\(item.originalName) · \(Int(item.remainingSeconds.rounded(.up)))s left")
    }

    private var icon: NSImage {
        NSWorkspace.shared.icon(forFile: item.cachedURL.path)
    }
}
