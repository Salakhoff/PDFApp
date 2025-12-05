import Foundation

struct PDFItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: URL
}
