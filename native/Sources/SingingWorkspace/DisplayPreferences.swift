import AppKit
import SwiftUI
import SongPrint

@MainActor
final class DisplayPreferences: ObservableObject {
    static let orderKey = "SingingWorkspace.readingOrder"
    static let appearanceKey = "SingingWorkspace.printAppearance"
    private let defaults: UserDefaults

    @Published var readingOrder: ReadingOrder {
        didSet {
            defaults.set(readingOrder.elements.map(\.rawValue), forKey: Self.orderKey)
        }
    }
    @Published var printAppearance: PrintAppearance {
        didSet {
            if let data = try? JSONEncoder().encode(printAppearance) {
                defaults.set(data, forKey: Self.appearanceKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: Self.orderKey) ?? []
        readingOrder = ReadingOrder(saved.compactMap(ReadingElement.init(rawValue:))) ?? .baseline
        printAppearance = defaults.data(forKey: Self.appearanceKey)
            .flatMap { try? JSONDecoder().decode(PrintAppearance.self, from: $0) } ?? .init()
    }
}

struct DisplaySettingsView: View {
    @ObservedObject var preferences: DisplayPreferences
    @State private var dragging: ReadingElement?
    @State private var dragOrigin: Int?
    @State private var dragDistance: CGFloat = 0
    private let rowHeight: CGFloat = 45

    var body: some View {
        Form {
            Section("歌詞の表示順") {
                Text("右側のつまみをドラッグして並び替えます。歌詞画面とPDF・Wordに同じ順番を使います。")
                    .font(.callout).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(preferences.readingOrder.elements, id: \.self) { element in
                        let index = preferences.readingOrder.elements.firstIndex(of: element)!
                        HStack(spacing: 12) {
                            Text(element.label)
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 38, height: 34)
                                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 3)
                                    .onChanged { value in
                                        if dragging != element {
                                            dragging = element
                                            dragOrigin = index
                                        }
                                        dragDistance = value.translation.height
                                    }
                                    .onEnded { value in
                                        if let dragOrigin {
                                            let target = max(0, min(preferences.readingOrder.elements.count - 1,
                                                dragOrigin + Int((value.translation.height / rowHeight).rounded())))
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                preferences.readingOrder = preferences.readingOrder.moving(element, to: target)
                                            }
                                        }
                                        dragging = nil
                                        dragOrigin = nil
                                        dragDistance = 0
                                    })
                                .accessibilityLabel("\(element.label)をドラッグして並び替え")
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 5)
                        .frame(height: rowHeight)
                        .background(dragging == element ? Color.teal.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                        .contentShape(Rectangle())
                        .offset(y: dragging == element ? dragDistance : 0)
                        .zIndex(dragging == element ? 1 : 0)
                        .contextMenu {
                            Button("上へ移動") { preferences.readingOrder = preferences.readingOrder.moving(element, by: -1) }
                                .disabled(index == 0)
                            Button("下へ移動") { preferences.readingOrder = preferences.readingOrder.moving(element, by: 1) }
                                .disabled(index == preferences.readingOrder.elements.count - 1)
                        }
                        if element != preferences.readingOrder.elements.last { Divider() }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("標準の並びに戻す") { preferences.readingOrder = .baseline }
            }
            Section("書き出し") {
                Text("PDFとWordのデザインと色は、画面のアクセントカラーとは別に設定できます。")
                    .foregroundStyle(.secondary)
                Picker("デザイン", selection: Binding(
                    get: { preferences.printAppearance.design },
                    set: { preferences.printAppearance.design = $0 }
                )) {
                    ForEach(PrintDesign.allCases, id: \.self) { design in
                        Text(design.label).tag(design)
                    }
                }
                ColorPicker("見出し・番号のアクセントカラー", selection: colorBinding(for: \.accent),
                            supportsOpacity: false)
                ColorPicker("母音核の色", selection: colorBinding(for: \.vowelNucleus),
                            supportsOpacity: false)
                Button("書き出しのデザインと色を標準に戻す") {
                    preferences.printAppearance = .init()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 590)
    }

    private func colorBinding(for keyPath: WritableKeyPath<PrintAppearance, PrintRGBColor>) -> Binding<Color> {
        Binding(
            get: {
                let value = preferences.printAppearance[keyPath: keyPath]
                return Color(red: Double(value.red) / 255, green: Double(value.green) / 255,
                             blue: Double(value.blue) / 255)
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                let component: (CGFloat) -> UInt8 = { UInt8((max(0, min(1, $0)) * 255).rounded()) }
                preferences.printAppearance[keyPath: keyPath] = .init(
                    red: component(rgb.redComponent), green: component(rgb.greenComponent),
                    blue: component(rgb.blueComponent))
            }
        )
    }
}
