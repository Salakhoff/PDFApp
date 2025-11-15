import PDFKit
import PencilKit

/// Обёртка UIDocument для работы с PDF-файлами через PDFKit.
/// Обеспечивает загрузку, сохранение и интеграцию рисунков PencilKit как PDF-аннотаций.
final class PDFKitDocument: UIDocument {
    // MARK: - Properties

    /// Основной PDF-документ, с которым ведётся работа.
    var pdfDocument: PDFDocument?

    // MARK: - Errors

    /// Ошибки, которые могут возникнуть при работе с документом.
    enum PDFDocumentError: Error {
        /// Ошибка при открытии документа.
        case open
        /// Ошибка при сохранении документа.
        case save
        /// Ошибка при закрытии документа.
        case close
    }

    // MARK: - Init

    override init(fileURL url: URL) {
        super.init(fileURL: url)
    }

    // MARK: - UIDocument Overrides

    /// Загружает содержимое PDF-файла в память.
    /// Вызывается автоматически системой при открытии документа через UIDocument.
    ///
    /// - Parameters:
    ///   - contents: Данные файла (Data для PDF).
    ///   - typeName: MIME-тип файла (например, "com.adobe.pdf").
    /// - Throws: PDFDocumentError.open, если тип файла не поддерживается.
    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let typeName = typeName else {
            throw PDFDocumentError.open
        }

        load(typeName: typeName, contents: contents)
    }

    /// Формирует данные для сохранения документа, добавляя рисунки PencilKit как PDF-аннотации.
    /// Вызывается автоматически при сохранении через UIDocument.
    ///
    /// - Parameter typeName: Тип файла для сохранения.
    /// - Returns: Данные PDF-документа с "встроенными" (burn-in) аннотациями.
    /// - Throws: Ничего не выбрасывает, возвращает пустой Data() в случае ошибки.
    override func contents(forType typeName: String) throws -> Any {
        guard let pdfDocument else { return Data() }

        // Добавляем рисунки как аннотации на все страницы с рисунками.
        for index in 0 ..< pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: index) else { continue }
            addDrawingAnnotation(page)
        }

        // Опция burnInAnnotationsOption "впечатывает" аннотации в PDF, делая их частью изображения.
        let options: [PDFDocumentWriteOption: Any] = [
            .burnInAnnotationsOption: true
        ]

        return pdfDocument.dataRepresentation(options: options) ?? Data()
    }
}

// MARK: - Private Helpers

extension PDFKitDocument {
    /// Загружает PDF-документ из данных файла по указанному типу.
    /// В текущей реализации поддерживается только стандартный PDF.
    ///
    /// - Parameters:
    ///   - typeName: MIME-тип файла.
    ///   - contents: Данные файла (Data).
    func load(typeName: String, contents: Any) {
        switch typeName {
        case "com.adobe.pdf":
            guard let data = contents as? Data else {
                pdfDocument = nil
                return
            }
            pdfDocument = PDFDocument(data: data)

        default:
            print("Unsupported typeName: \(typeName)")
        }
    }

    /// Добавляет рисунок PencilKit со страницы как PDF-аннотацию типа .stamp.
    /// Аннотация сохраняет данные рисунка и метаинформацию (высоту MediaBox) для корректной отрисовки.
    ///
    /// - Parameter page: Страница PDF (должна быть PDFDocumentPage с данными drawing).
    func addDrawingAnnotation(_ page: PDFPage) {
        guard let page = page as? PDFDocumentPage else { return }

        let drawing = page.drawing
        // Пропускаем страницы без рисунков, чтобы не создавать пустые аннотации.
        guard !drawing.strokes.isEmpty else { return }

        // Получаем размеры страницы для правильного позиционирования аннотации.
        let mediaBoxBounds = page.bounds(for: .cropBox)
        let mediaBoxHeight = mediaBoxBounds.height

        // Сохраняем метаинформацию для корректной отрисовки (нужна для преобразования координат).
        let userDefinedAnnotationProperties: [AnyHashable: Any] = [
            DrawingAnnotation.AnnotationKey.mediaBoxHeight: NSNumber(value: mediaBoxHeight)
        ]

        // Создаём кастомную аннотацию типа .stamp (штамп), которая будет рисоваться поверх страницы.
        let newAnnotation = DrawingAnnotation(
            bounds: mediaBoxBounds,
            forType: .stamp,
            withProperties: userDefinedAnnotationProperties
        )

        // Сохраняем сериализованные данные PKDrawing в аннотацию.
        let codedData = drawing.dataRepresentation()
        newAnnotation.setValue(
            codedData,
            forAnnotationKey: DrawingAnnotation.AnnotationKey.drawingData
        )

        // Добавляем аннотацию на страницу.
        page.addAnnotation(newAnnotation)
    }
}

// MARK: - Async API

@MainActor
extension PDFKitDocument {
    /// Асинхронное открытие документа с использованием async/await.
    /// Оборачивает UIDocument.open(completionHandler:) в async API.
    func openAsync() async throws {
        try await withCheckedThrowingContinuation { continuation in
            open { success in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PDFDocumentError.open)
                }
            }
        }
    }

    /// Асинхронное сохранение документа в указанное место.
    /// Оборачивает UIDocument.save(to:for:completionHandler:) в async API.
    ///
    /// - Parameters:
    ///   - url: Конечный URL файла (включая имя файла).
    ///   - operation: Тип операции сохранения (например, .forOverwriting).
    func saveAsync(to url: URL, for operation: UIDocument.SaveOperation) async throws {
        try await withCheckedThrowingContinuation { continuation in
            save(to: url, for: operation) { success in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PDFDocumentError.save)
                }
            }
        }
    }

    /// Асинхронное закрытие документа.
    /// Оборачивает UIDocument.close(completionHandler:) в async API.
    func closeAsync() async throws {
        try await withCheckedThrowingContinuation { continuation in
            close { success in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PDFDocumentError.close)
                }
            }
        }
    }
}
