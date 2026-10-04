import AppKit
import LivepaperWorkshop
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Edit > Paste in the library window, as Import takes it: files and folders
    /// are imported; a Workshop link, or an item's number, is got from Steam.
    func pastesIntoLibrary() -> some View {
        modifier(LibraryPaste())
    }
}

private struct LibraryPaste: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(WorkshopModel.self) private var workshop

    func body(content: Content) -> some View {
        content.onPasteCommand(of: [.fileURL, .url, .plainText]) { _ in paste() }
    }

    private func paste() {
        let board = NSPasteboard.general
        let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty, model.canImport {
            model.importItems(at: files)
        } else if !workshop.get(pasted: urls.first?.absoluteString ?? board.string(forType: .string) ?? "") {
            NSSound.beep()
        }
    }
}

extension WorkshopModel {
    /// Links dropped on the library window: each Workshop item among them is got. Answers whether there was one.
    func get(dropped urls: [URL]) -> Bool {
        let items = urls.filter { !$0.isFileURL }.map(\.absoluteString).filter { get(pasted: $0) }
        return !items.isEmpty
    }
}
