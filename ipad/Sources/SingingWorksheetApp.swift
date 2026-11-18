import SwiftUI

@main
struct SingingWorksheetApp: App {
    var body: some Scene {
        WindowGroup {
            WorksheetScreen()
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

private struct WorksheetScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WorksheetViewController { WorksheetViewController() }
    func updateUIViewController(_ controller: WorksheetViewController, context: Context) {}
}
