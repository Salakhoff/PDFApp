import PDFKit
import PencilKit

/// Кастомная страница PDF, которая хранит данные рисования PencilKit.
/// Наследуется от PDFPage для интеграции с PDFKit и добавляет возможность сохранения штрихов.
final class PDFDocumentPage: PDFPage {
    /// Данные рисования PencilKit, связанные с этой страницей.
    var drawing: PKDrawing = PKDrawing()
}
