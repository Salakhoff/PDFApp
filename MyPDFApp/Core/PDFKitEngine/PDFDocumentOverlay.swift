import PDFKit
import UIKit
import PencilKit

/// Провайдер overlay-вью для PDFKit, добавляющий canvas для рисования поверх каждой страницы.
/// Управляет жизненным циклом PDFKitDrawingView и синхронизацией рисунков со страницами.
final class PDFDocumentOverlay: NSObject, PDFPageOverlayViewProvider {

    // MARK: - Properties

    /// Словарь для хранения соответствия страниц и их overlay-вью.
    /// Используется для переиспользования view и синхронизации состояния.
    var pageToViewMapping = [PDFDocumentPage: PDFKitDrawingView]()

    // MARK: - PDFPageOverlayViewProvider

    /// Создаёт или возвращает существующую overlay-вью для страницы PDF.
    /// Вызывается PDFKit, когда страница появляется на экране.
    ///
    /// - Parameters:
    ///   - pdfView: PDFView, который запрашивает overlay.
    ///   - page: Страница PDF, для которой нужен overlay.
    /// - Returns: UIView с canvas для рисования или nil, если страница не PDFDocumentPage.
    func pdfView(_ pdfView: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let page = page as? PDFDocumentPage else { return nil }

        let overlayView: PDFKitDrawingView

        // Переиспользуем существующую view, если она уже есть (для оптимизации производительности).
        if let existingView = pageToViewMapping[page] {
            // ВАЖНО: Сначала сохраняем текущий drawing из canvas в страницу,
            // если у view была другая страница (переиспользование view для другой страницы)
            if let previousPage = existingView.page, previousPage !== page {
                previousPage.drawing = existingView.canvasView.drawing
            }
            
            existingView.page = page
            overlayView = existingView
        } else {
            // Создаём новую view при первом показе страницы.
            let canvasView = PDFKitDrawingView(frame: .zero)
            canvasView.backgroundColor = .clear
            canvasView.page = page

            // Настраиваем коллбек для синхронизации рисунков со страницей.
            canvasView.onDrawingChanged = { [weak page] drawing in
                // Сохраняем изменения синхронно при каждом изменении
                page?.drawing = drawing
            }

            pageToViewMapping[page] = canvasView
            overlayView = canvasView
        }

        // Восстанавливаем текущий рисунок страницы в canvas.
        // ВАЖНО: Делаем это ПОСЛЕ настройки коллбека, чтобы не вызвать лишние обновления
        overlayView.canvasView.drawing = page.drawing

        return overlayView
    }

    /// Вызывается перед отображением overlay-вью (можно использовать для настройки).
    /// В текущей реализации не используется, но оставлен для будущих расширений.
    ///
    /// - Parameters:
    ///   - pdfView: PDFView, отображающий страницу.
    ///   - overlayView: Overlay-вью, которая будет показана.
    ///   - page: Страница, для которой отображается overlay.
    func pdfView(
        _ pdfView: PDFView,
        willDisplayOverlayView overlayView: UIView,
        for page: PDFPage
    ) {
        // При отображении страницы убеждаемся, что drawing синхронизирован
        guard let overlayView = overlayView as? PDFKitDrawingView,
              let page = page as? PDFDocumentPage else { return }
        
        // Сохраняем текущий drawing из canvas в страницу (на случай, если были изменения)
        page.drawing = overlayView.canvasView.drawing
    }

    /// Вызывается перед скрытием overlay-вью.
    /// Сохраняет текущий рисунок в страницу и удаляет view из словаря для освобождения памяти.
    ///
    /// - Parameters:
    ///   - pdfView: PDFView, скрывающий страницу.
    ///   - overlayView: Overlay-вью, которая будет скрыта.
    ///   - page: Страница, для которой скрывается overlay.
    func pdfView(
        _ pdfView: PDFView,
        willEndDisplayingOverlayView overlayView: UIView,
        for page: PDFPage
    ) {
        guard
            let overlayView = overlayView as? PDFKitDrawingView,
            let page = page as? PDFDocumentPage
        else { return }

        // ВАЖНО: Сохраняем текущий рисунок в страницу перед удалением view.
        // Это гарантирует, что все изменения (включая стирание ластиком) будут сохранены.
        page.drawing = overlayView.canvasView.drawing

        // Удаляем из словаря, чтобы освободить память (PDFKit будет переиспользовать view при следующем показе).
        pageToViewMapping.removeValue(forKey: page)
    }
    
    // MARK: - Public API
    
    /// Принудительно сохраняет все изменения во всех активных overlay view.
    /// Полезно вызывать перед сохранением документа или сменой страницы.
    /// Гарантирует, что все изменения (включая стирание ластиком) синхронизированы с PDFDocumentPage.
    func saveAllDrawings() {
        for (page, overlayView) in pageToViewMapping {
            page.drawing = overlayView.canvasView.drawing
        }
    }
}
