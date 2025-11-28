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
    /// - Returns: Данные PDF-документа
    /// - Throws: Ничего не выбрасывает, возвращает пустой Data() в случае ошибки.
    override func contents(forType typeName: String) throws -> Any {
        guard let pdfDocument else { return Data() }

        // Добавляем рисунки как аннотации на все страницы с рисунками.
        for index in 0 ..< pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: index) else { continue }
            addDrawingAnnotation(page)
        }

        // Сохраняем PDF с аннотациями как отдельными объектами (без burn-in).
        // Это позволяет другим приложениям редактировать аннотации.
        return pdfDocument.dataRepresentation() ?? Data()
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

extension PDFKitDocument {
    
    /// Экспортирует аннотации документа в JSON формат (Data)
    /// Используется для отправки на бэкенд вместе с PDF файлом.
    func exportAnnotationsAsJSON() -> Data? {
        guard let pdfDocument = pdfDocument else { return nil }
        
        var annotationsDTO: [DrawingAnnotationDTO] = []
        
        for index in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: index) as? PDFDocumentPage else { continue }
            
            // Если на странице есть рисунок
            if !page.drawing.strokes.isEmpty {
                let mediaBox = page.bounds(for: .mediaBox)
                // Используем наш extension для конвертации
                let dto = page.drawing.toDTO(pageIndex: index, mediaBox: mediaBox)
                annotationsDTO.append(dto)
            }
        }
        
        // Сериализуем массив DTO в JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // Для читаемости, можно убрать в продакшене
        return try? encoder.encode(annotationsDTO)
    }
    
    /// Импортирует аннотации из JSON данных и применяет их к документу.
    /// Используется при получении обновленных данных с бэкенда/Android.
    /// - Returns: Bool - успешно ли прошел импорт
    @MainActor
    func importAnnotationsFromJSON(_ jsonData: Data) -> Bool {
        guard let pdfDocument = pdfDocument else {
            print("❌ importAnnotationsFromJSON: pdfDocument is nil")
            return false
        }
        
        let decoder = JSONDecoder()
        guard let annotationsDTO = try? decoder.decode([DrawingAnnotationDTO].self, from: jsonData) else {
            print("❌ Ошибка декодирования JSON аннотаций")
            return false
        }
        
        print("📥 Начало импорта аннотаций. Найдено страниц с данными: \(annotationsDTO.count)")
        
        for dto in annotationsDTO {
            // Пропускаем невалидные индексы
            guard dto.pageIndex >= 0 && dto.pageIndex < pdfDocument.pageCount else {
                print("⚠️ Пропуск невалидного индекса страницы: \(dto.pageIndex)")
                continue
            }
            
            // Получаем страницу (должна быть PDFDocumentPage благодаря делегату)
            guard let page = pdfDocument.page(at: dto.pageIndex) as? PDFDocumentPage else {
                print("⚠️ Страница \(dto.pageIndex) не является PDFDocumentPage (делегат не сработал?)")
                continue
            }
            
            // 1. Восстанавливаем "живой" рисунок
            let newDrawing = dto.toPKDrawing()
            page.drawing = newDrawing
            print("✅ Страница \(dto.pageIndex): Восстановлено штрихов: \(newDrawing.strokes.count)")
            
            // 2. Удаление старых аннотаций (дубликатов из PDF-файла)
            // Ищем любые аннотации, которые похожи на наши рисунки
            let annotationsToRemove = page.annotations.filter { annotation in
                // А. Если это наш кастомный класс
                if annotation is DrawingAnnotation { return true }
                
                // Б. Если аннотация содержит наши данные (ключ drawingData)
                // Используем строковый ключ для надежности
                if annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "drawingData")) != nil {
                    return true
                }
                
                // В. Если это Stamp, который мы сами создали ранее (можно проверить наличие ключа mediaBoxHeight)
                if annotation.type == "Stamp",
                   annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "pdfPageMediaBoxHeight")) != nil {
                    return true
                }
                
                return false
            }
            
            if !annotationsToRemove.isEmpty {
                print("🗑 Страница \(dto.pageIndex): Удалено старых PDF-аннотаций: \(annotationsToRemove.count)")
                for annotation in annotationsToRemove {
                    page.removeAnnotation(annotation)
                }
            } else {
                print("ℹ️ Страница \(dto.pageIndex): Старых аннотаций не найдено (возможно, они уже удалены или не распознаны)")
            }
        }
        
        return true
    }
}
