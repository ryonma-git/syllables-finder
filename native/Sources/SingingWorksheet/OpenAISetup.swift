import SwiftUI
import Security
import SongServices

/// This distribution app never reads credentials belonging to the authoring workspace.
@MainActor enum WorksheetKeychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "jp.singingworkspace.worksheet.openai",
        kSecAttrAccount as String: "https://api.openai.com/v1"
    ]

    static func read() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw ProviderError.unavailable("キーチェーンのキーを読み取れませんでした（\(status)）。")
        }
        return key
    }

    static func save(_ key: String) throws {
        let values: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ProviderError.unavailable("キーチェーンに保存できませんでした（\(status)）。") }
    }

    static func forget() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ProviderError.unavailable("キーを削除できませんでした（\(status)）。") }
    }
}

struct OpenAISetup: View {
    let lineCount: Int
    let start: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var savedKey = ""
    @State private var remember = false
    @State private var status = ""
    private var suppliedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OpenAIで読みと訳を補う").font(.title2.bold())
            Text("この教材の歌詞（\(lineCount)行）をOpenAIに送り、音節・IPA・カタカナ・単語訳・行の訳を補います。手直しした項目は保持します。")
            Text("モデル  " + APIModelConfiguration.openAIModel).font(.callout)
            SecureField(savedKey.isEmpty ? "ご自身のOpenAI APIキー" : "設定済みのキーを使用", text: $key)
                .textFieldStyle(.roundedBorder)
            Toggle("入力したキーをこのMacのキーチェーンに保存する", isOn: $remember)
                .disabled(suppliedKey.isEmpty)
            Text("API料金は、ご自身のキーを発行した組織に計上されます。").font(.caption).foregroundStyle(.secondary)
            if !savedKey.isEmpty {
                Button("保存済みキーをこのMacから削除") {
                    do { try WorksheetKeychain.forget(); savedKey = ""; status = "保存済みキーを削除しました。" }
                    catch { status = error.localizedDescription }
                }
            }
            if !status.isEmpty { Text(status).font(.callout).accessibilityLabel(status) }
            HStack {
                Button("閉じる", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("歌詞を送信して補完") {
                    let value = suppliedKey.isEmpty ? savedKey : suppliedKey
                    do {
                        if remember && !suppliedKey.isEmpty { try WorksheetKeychain.save(value) }
                        start(value); dismiss()
                    } catch { status = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(suppliedKey.isEmpty && savedKey.isEmpty)
            }
        }.padding(24).frame(width: 490)
        .onAppear {
            do { savedKey = try WorksheetKeychain.read() } catch { status = error.localizedDescription }
        }
    }
}
