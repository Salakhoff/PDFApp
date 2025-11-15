import Foundation

/// Модель PDF файла, используемая в списках и редакторе.
struct PDFItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: URL
}
