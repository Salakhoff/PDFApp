import PDFKit
import SwiftUI
import PencilKit

/// Главный класс для отображения и редактирования PDF-документов.
/// Интегрирует PDFKit, PencilKit и управляет режимами просмотра/рисования, масштабированием и сохранением.
@MainActor
final class PDFDocumentView: PDFView {
    
    // MARK: Properties
    
    /// Индекс текущей отображаемой страницы (обновляется при скролле).
    private(set) var currentPageIndex: Int = 0
    
    /// Обёртка UIDocument для работы с PDF-файлом через файловую систему.
    private var pdfDocument: PDFKitDocument?
    
    /// Провайдер overlay-вью для добавления canvas рисования поверх страниц.
    private let overlay = PDFDocumentOverlay()
    
    #warning("Выбор определенных инструментов доступен только с iOS 18.")
    // init(toolItems: [PKToolPickerItem])
    private let toolPicker = PKToolPicker()
    
    
    // MARK: Init
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    // MARK: Public API
    
    /// Загружает PDF-документ из указанного URL и ищет JSON с аннотациями.
    func loadPDF(url: URL?) {
        guard let url else { return }
        
        resetDrawingState()
        
        let document = PDFKitDocument(fileURL: url)
        self.pdfDocument = document
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            do {
                try await document.openAsync()
                
                // --- FIX: Устанавливаем делегат СРАЗУ после открытия ---
                // Это критически важно сделать ДО того, как мы начнем обращаться к страницам
                // в importAnnotationsFromJSON. Иначе PDFKit создаст стандартные PDFPage,
                // у которых нет свойства drawing, и импорт не сработает.
                document.pdfDocument?.delegate = self
                // -------------------------------------------------------
                
                // --- ЛОГИКА ЗАГРУЗКИ JSON ---
                let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
                
                if FileManager.default.fileExists(atPath: jsonURL.path) {
                    if let data = try? Data(contentsOf: jsonURL) {
                        let success = document.importAnnotationsFromJSON(data)
                        if success {
                            print("✅ Аннотации восстановлены из JSON")
                        }
                    }
                }
                // -----------------------------
                
                configureDocumentLoading(success: true)
            } catch {
                print("❌ Ошибка открытия PDF: \(error)")
            }
        }
    }
    
    /// Переключает режим работы между просмотром и рисованием.
    func drawing(isEnable: Bool) {
        startDrawing(isEnable: isEnable)
        isScrollEnabled = !isEnable
    }
    
    /// Сохраняет текущий документ с рисунками и JSON-аннотациями в указанную директорию.
    func saveTo(url: URL, fileName: String) async throws {
        guard let document = pdfDocument else { return }
        
        // 1. Пути к файлам
        let pdfURL = url.appendingPathComponent(fileName)
        // Имя JSON файла такое же, но с расширением .json
        let jsonFileName = fileName.replacingOccurrences(of: ".pdf", with: ".json")
        let jsonURL = url.appendingPathComponent(jsonFileName)
        
        // 2. Экспорт аннотаций в JSON (до закрытия документа!)
        print("💾 Начинаем сохранение...")
        
        let annotationsData = document.exportAnnotationsAsJSON()
        
        // --- LOG JSON ---
        if let data = annotationsData, let jsonString = String(data: data, encoding: .utf8) {
            print("\n📦 --- JSON PAYLOAD ДЛЯ БЭКЕНДА ---")
            print(jsonString)
            print("📦 -------------------------------\n")
        }
        // ----------------
        
        resetDrawingState()
        
        // 3. Закрываем документ перед перезаписью PDF
        try await document.closeAsync()
        
        // 4. Сохраняем PDF (без burn-in, благодаря изменениям в PDFKitDocument)
        try await document.saveAsync(to: pdfURL, for: .forOverwriting)
        
        // 5. Сохраняем JSON файл рядом
        if let data = annotationsData {
            try data.write(to: jsonURL)
            print("✅ JSON аннотаций сохранён: \(jsonURL.lastPathComponent)")
        }
        
        print("✅ PDF сохранён по пути: \(pdfURL)")
        
        // После сохранения нужно переоткрыть документ, чтобы продолжить работу
        try await document.openAsync()
        
        // --- FIX: Устанавливаем делегат СРАЗУ после переоткрытия ---
        document.pdfDocument?.delegate = self
        // -----------------------------------------------------------
        
        configureDocumentLoading(success: true)
    }
    
    /// Отменяет последний штрих рисования на текущей странице.
    func undoDrawing() {
        guard
            let pdfPage = currentPage as? PDFDocumentPage,
            let overlayView = overlay.pageToViewMapping[pdfPage]
        else { return }

        overlayView.canvasView.undoManager?.undo()
    }

    /// Повторяет последнюю отменённую операцию рисования на текущей странице.
    func redoDrawing() {
        guard
            let pdfPage = currentPage as? PDFDocumentPage,
            let overlayView = overlay.pageToViewMapping[pdfPage]
        else { return }

        overlayView.canvasView.undoManager?.redo()
    }
}

// MARK: - Private Configuration

private extension PDFDocumentView {
    
    /// Получает внутренний UIScrollView PDFView для управления скроллом.
    /// PDFView содержит scrollView в своей иерархии, но не предоставляет публичный доступ к нему.
    var privateScrollView: UIScrollView? {
        subviews.first as? UIScrollView
    }
    
    /// Управляет возможностью скролла PDF
    var isScrollEnabled: Bool {
        get { privateScrollView?.isScrollEnabled ?? true }
        set { privateScrollView?.isScrollEnabled = newValue }
    }
    
    /// Настраивает базовые параметры PDFView
    func configure() {
        autoScales = true // Автоматическое масштабирование под размер экрана.
        displayMode = .singlePageContinuous // Режим прокрутки одной страницы за раз.
        pageShadowsEnabled = false // Отключаем тени для более чистого вида.
        displaysPageBreaks = true // Показываем разрывы между страницами.
        isInMarkupMode = true // Включаем режим разметки для работы с аннотациями.
        displayBox = .mediaBox // Используем MediaBox для координат (стандарт PDF).
        interpolationQuality = .high // Высокое качество интерполяции при масштабировании.
        usePageViewController(false) // Отключаем UIPageViewController для лучшей производительности.
    }
    
    /// Настраивает PDFView после успешной загрузки документа.
    /// Устанавливает delegate, overlay provider, масштабирование и привязывает документ.
    func configureDocumentLoading(success: Bool) {
        guard success else { return }
        
        // При загрузке нового документа очищаем кэш overlay-вью.
        overlay.pageToViewMapping.removeAll()
        
        // Устанавливаем delegate для кастомизации страниц (возвращаем PDFDocumentPage вместо стандартных).
        pdfDocument?.pdfDocument?.delegate = self
        
        // Подключаем overlay provider для добавления canvas рисования поверх страниц.
        pageOverlayViewProvider = overlay
        
        // Привязываем загруженный PDF-документ к PDFView.
        document = pdfDocument?.pdfDocument
        
        // Настраиваем масштабирование: минимум = размер по экрану, максимум = 4x для детального просмотра.
        minScaleFactor = scaleFactorForSizeToFit
        maxScaleFactor = 4.0
        scaleFactor = scaleFactorForSizeToFit
        autoScales = true
    }
}

// MARK: - Drawing Management

private extension PDFDocumentView {
    
    /// Активирует или деактивирует режим рисования на текущей странице.
    /// Источником правды для состояния рисования считается видимость PKToolPicker (`isVisible`).
    ///
    /// - Parameter isEnable: Желаемое состояние режима рисования.
    func startDrawing(isEnable: Bool) {
        guard let pdfPage = currentPage as? PDFDocumentPage else { return }
        guard let overlayView = overlay.pageToViewMapping[pdfPage] else { return }

        guard overlayView.window != nil else { return }
        
        let targetVisible = isEnable
        let currentVisible = toolPicker.isVisible

        overlayView.enable(mode: targetVisible ? .drawing : .default)
        isScrollEnabled = !targetVisible

        guard currentVisible != targetVisible else { return }

        if targetVisible {
            toolPicker.addObserver(overlayView.canvasView)
            toolPicker.setVisible(true, forFirstResponder: overlayView.canvasView)
            overlayView.canvasView.becomeFirstResponder()
        } else {
            toolPicker.setVisible(false, forFirstResponder: overlayView.canvasView)
            toolPicker.removeObserver(overlayView.canvasView)
            overlayView.canvasView.resignFirstResponder()
        }
    }
    
    /// Сбрасывает состояние рисования и очищает связи с ToolPicker.
    /// Необходимо вызывать перед загрузкой нового документа или перезагрузкой текущего.
    func resetDrawingState() {
        // Проходимся по всем активным overlay view
        overlay.pageToViewMapping.values.forEach { view in
            // Если тулпикер был видим для этой вьюхи — скрываем
            if toolPicker.isVisible {
                toolPicker.setVisible(false, forFirstResponder: view.canvasView)
            }
            // Отписываемся и убираем фокус
            toolPicker.removeObserver(view.canvasView)
            view.canvasView.resignFirstResponder()
        }
        
        // Очищаем кэш
        overlay.pageToViewMapping.removeAll()
    }
}

// MARK: - PDFDocumentDelegate

extension PDFDocumentView: PDFDocumentDelegate {
    
    /// Указывает PDFKit использовать кастомный класс страниц вместо стандартного PDFPage.
    /// Это позволяет нам добавлять свойства (например, drawing) к страницам.
    func classForPage() -> AnyClass {
        PDFDocumentPage.self
    }
}

// MARK: - UIScrollViewDelegate

extension PDFDocumentView: UIScrollViewDelegate {
    
    /// Обновляет индекс текущей страницы после завершения скролла.
    /// Вызывается автоматически при остановке прокрутки для отслеживания видимой страницы.
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard
            let page = currentPage,
            let index = document?.index(for: page)
        else {
            return
        }
        
        currentPageIndex = index
    }
}
