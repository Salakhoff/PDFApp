import SwiftUI
import PDFKit

/// Обёртка над `PDFDocumentView` для использования в SwiftUI.
/// Создаёт и настраивает PDFView, передаёт его во ViewModel и обновляет режим рисования.
struct PDFKitViewRepresentable: UIViewRepresentable {

    // MARK: Properties

    /// Обязательный URL PDF-документа для загрузки.
    let pdfURL: URL

    /// Флаг режима рисования: true = рисование включено, false = обычный просмотр.
    let drawingEnabled: Bool

    /// Коллбек, вызываемый после создания PDFView, чтобы передать его во ViewModel.
    let onPDFViewCreated: (PDFDocumentView) -> Void

    // MARK: UIViewRepresentable

    /// Создаёт и конфигурирует экземпляр `PDFDocumentView`.
    func makeUIView(context: Context) -> PDFDocumentView {
        let pdfView = PDFDocumentView(frame: .zero)
        pdfView.loadPDF(url: pdfURL)
        onPDFViewCreated(pdfView)
        return pdfView
    }

    /// Обновляет состояние `PDFDocumentView` при изменении SwiftUI-состояния.
    /// Здесь мы синхронизируем только режим рисования.
    func updateUIView(_ uiView: PDFDocumentView, context: Context) {
        uiView.drawing(isEnable: drawingEnabled)
    }
}
