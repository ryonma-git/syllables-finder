import SwiftUI
import SongPrint

@MainActor
final class DisplayPreferences: ObservableObject {
    static let orderKey = "SingingWorkspace.readingOrder"
    private let defaults: UserDefaults

    @Published var readingOrder: ReadingOrder {
        didSet {
            defaults.set(readingOrder.elements.map(\.rawValue), forKey: Self.orderKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: Self.orderKey) ?? []
        readingOrder = ReadingOrder(saved.compactMap(ReadingElement.init(rawValue:))) ?? .baseline
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
                Text("PDFとWordは、書き出しを始めた時点の表示順で作成します。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 410)
    }
}
