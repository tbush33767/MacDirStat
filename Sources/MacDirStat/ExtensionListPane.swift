import MacDirStatCore
import SwiftUI
import UniformTypeIdentifiers

/// The file-extension table: color swatch (matching treemap tiles), extension,
/// description, total size, share, and file count.
struct ExtensionListPane: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\ExtStat.bytes, order: .reverse)]

    var body: some View {
        @Bindable var model = model
        let stats = (model.result?.extensionStats ?? []).sorted(using: sortOrder)
        let palette = model.result?.palette

        Table(stats, selection: $model.selectedExtension, sortOrder: $sortOrder) {
            TableColumn("Extension", value: \.ext) { stat in
                HStack(spacing: 6) {
                    swatch(for: stat, palette: palette)
                    Text(stat.ext.isEmpty ? "<none>" : ".\(stat.ext)")
                }
            }
            .width(min: 70, ideal: 90)

            TableColumn("Size", value: \.bytes) { stat in
                Text(Format.bytes(stat.bytes))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 70)

            TableColumn("%", value: \.percent) { stat in
                Text(Format.percent(stat.percent))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 44, ideal: 50)

            TableColumn("Files", value: \.fileCount) { stat in
                Text(Format.count(stat.fileCount))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 60)

            TableColumn("Description", value: \.ext) { stat in
                Text(Self.description(for: stat.ext))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 140)
        }
        .font(.callout)
    }

    private func swatch(for stat: ExtStat, palette: Palette?) -> some View {
        let rgb = palette?.color(forExtension: stat.ext) ?? Palette.grey
        return RoundedRectangle(cornerRadius: 2)
            .fill(Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255))
            .frame(width: 12, height: 12)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.quaternary))
    }

    @MainActor private static var descriptionCache: [String: String] = [:]

    private static func description(for ext: String) -> String {
        if let cached = descriptionCache[ext] { return cached }
        let description: String
        if ext.isEmpty {
            description = "No extension"
        } else {
            description = UTType(filenameExtension: ext)?.localizedDescription ?? "\(ext) file"
        }
        descriptionCache[ext] = description
        return description
    }
}
