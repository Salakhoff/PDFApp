import SwiftUI
import PDFKit

/// SwiftUI обёртка над PDFThumbnailView для отображения миниатюр страниц.
/// PDFThumbnailView автоматически синхронизируется с PDFView: выбор миниатюры переключает страницу,
/// прокрутка PDFView обновляет выделение миниатюры.
struct PDFThumbnailViewRepresentable: UIViewRepresentable {

    // MARK: - Properties

    /// PDFView, с которым синхронизируются миниатюры.
    let pdfView: PDFDocumentView

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> PDFThumbnailView {
        let thumbnailView = PDFThumbnailView()
        thumbnailView.pdfView = pdfView
        thumbnailView.layoutMode = .vertical
        thumbnailView.thumbnailSize = CGSize(width: 100, height: 100)
        thumbnailView.backgroundColor = UIColor.systemBackground
        return thumbnailView
    }

    func updateUIView(_ uiView: PDFThumbnailView, context: Context) {
        
    }
}
