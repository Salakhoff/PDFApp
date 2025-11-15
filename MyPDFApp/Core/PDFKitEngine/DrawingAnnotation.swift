import PDFKit
import PencilKit

/// Кастомная PDF-аннотация для отрисовки рисунков PencilKit поверх PDF-страниц.
/// Сохраняет данные рисования и метаинформацию (высоту MediaBox) для корректной отрисовки.
final class DrawingAnnotation: PDFAnnotation {

    // MARK: - Annotation Keys

    /// Ключи для хранения данных аннотации в PDF.
    enum AnnotationKey {
        /// Ключ для сохранения сериализованных данных PKDrawing.
        static let drawingData = PDFAnnotationKey(rawValue: "drawingData")
        /// Ключ для сохранения высоты MediaBox страницы (нужен для корректного преобразования координат).
        static let mediaBoxHeight = PDFAnnotationKey(rawValue: "pdfPageMediaBoxHeight")
    }

    // MARK: - Private Properties

    /// Десериализованные данные рисования PencilKit из аннотации.
    private var drawing: PKDrawing? {
        guard let data = value(forAnnotationKey: AnnotationKey.drawingData) as? Data else {
            return nil
        }

        return try? PKDrawing(data: data)
    }

    /// Высота MediaBox страницы на момент создания аннотации.
    /// Используется для корректного преобразования координат при отрисовке (PDF использует инвертированную Y-ось).
    private var mediaBoxHeight: CGFloat? {
        guard let number = value(forAnnotationKey: AnnotationKey.mediaBoxHeight) as? NSNumber else {
            return nil
        }

        return CGFloat(truncating: number)
    }

    // MARK: - Drawing

    /// Отрисовывает рисунок PencilKit поверх PDF-страницы с учётом масштаба и преобразования координат.
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard page is PDFDocumentPage else { return }
        guard let drawing, let mediaBoxHeight else { return }

        UIGraphicsPushContext(context)
        context.saveGState()

        context.concatenate(makePDFTransform(verticalShift: mediaBoxHeight))

        let image = drawing.image(
            from: drawing.bounds,
            scale: currentDisplayScale(from: context)
        )
        image.draw(in: drawing.bounds)

        context.restoreGState()
        UIGraphicsPopContext()
    }
}

// MARK: - Private Helpers

private extension DrawingAnnotation {
    /// Создаёт аффинное преобразование для корректной отрисовки в PDF-системе координат.
    /// PDF использует координаты снизу-вверх, а UIKit/UIKit — сверху-вниз, поэтому нужна инверсия Y.
    ///
    /// - Parameter verticalShift: Высота MediaBox страницы для сдвига координат.
    /// - Returns: CGAffineTransform для преобразования координат.
    func makePDFTransform(verticalShift: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: 1.0, y: -1.0)
            .translatedBy(x: 0.0, y: -verticalShift)
    }

    /// Определяет текущий масштаб отображения из контекста для корректной отрисовки штрихов.
    /// Использует компонент `a` матрицы преобразования (scale по X).
    ///
    /// - Parameter context: CGContext для анализа масштаба.
    /// - Returns: Масштаб отображения (минимум 1.0, чтобы избежать нулевых/отрицательных значений).
    func currentDisplayScale(from context: CGContext) -> CGFloat {
        let scale = context.ctm.a
        return scale > 0 ? scale : 1.0
    }
}
