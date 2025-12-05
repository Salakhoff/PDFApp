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
    
    /// Флаг активного режима рисования.
    private var drawingEnabled = false
    
    /// Менеджер состояния инструментов рисования.
    var toolStateManager: ToolStateManager?
    
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
    
    func updateToolForAllCanvases() {
        guard let toolStateManager = toolStateManager else { return }
        
        overlay.pageToViewMapping.values.forEach { overlayView in
            toolStateManager.applyTool(to: overlayView.canvasView)
        }
    }
    
    /// Переключает режим работы между просмотром и рисованием.
    func drawing(isEnable: Bool) {
        drawingEnabled = isEnable
        startDrawing(isEnable: isEnable)
        isScrollEnabled = !isEnable
    }
    
    func saveTo(url: URL, fileName: String) async throws {
        guard let document = pdfDocument else { return }
        
        // 1. Пути к файлам
        let pdfURL = url.appendingPathComponent(fileName)
        
        // 2. Закрываем документ перед перезаписью PDF
        try await document.closeAsync()
        
        // 3. Сохраняем PDF
        try await document.saveAsync(to: pdfURL, for: .forOverwriting)
        
        print("✅ PDF сохранён по пути: \(pdfURL)")
        
        // 4. Переоткрываем документ для дальнейшей работы
        try await document.openAsync()
        
        // 5. Устанавливаем делегат СРАЗУ после открытия (критически важно!)
        document.pdfDocument?.delegate = self
        
        // 6. Загружаем аннотации из JSON (если файл существует)
        let jsonURL = pdfURL.deletingPathExtension().appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            if let data = try? Data(contentsOf: jsonURL) {
                let success = document.importAnnotationsFromJSON(data)
                if success {
                    print("✅ Аннотации восстановлены из JSON после сохранения")
                }
            }
        }
        
        // 7. Настраиваем view после перезагрузки
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
    
    func exportAnnotationsJSON() -> Data? {
        pdfDocument?.exportAnnotationsAsJSON()
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

// MARK: - Drawing Management

private extension PDFDocumentView {
    
    /// Получает все видимые страницы в текущей области просмотра.
    /// - Returns: Массив видимых PDFDocumentPage
    func getVisiblePages() -> [PDFDocumentPage] {
        guard let document = document else { return [] }
        
        var visiblePages: [PDFDocumentPage] = []
        let visibleRect = bounds
        
        // Проверяем каждую страницу документа
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) as? PDFDocumentPage else { continue }
            
            // Получаем bounds страницы в координатах PDFView
            let pageBounds = convert(page.bounds(for: .mediaBox), from: page)
            
            // Проверяем, пересекается ли страница с видимой областью
            if visibleRect.intersects(pageBounds) {
                visiblePages.append(page)
            }
        }
        
        return visiblePages
    }
    
    /// Активирует или деактивирует режим рисования на всех видимых страницах.
    /// Применяет инструмент из ToolStateManager к canvas.
    ///
    /// - Parameter isEnable: Желаемое состояние режима рисования.
    func startDrawing(isEnable: Bool) {
        // Получаем все видимые страницы
        let visiblePages = getVisiblePages()
        
        guard !visiblePages.isEmpty else { return }
        
        isScrollEnabled = !isEnable
        
        // Активируем рисование для всех видимых страниц
        for pdfPage in visiblePages {
            guard let overlayView = overlay.pageToViewMapping[pdfPage] else { continue }
            guard overlayView.window != nil else { continue }
            
            overlayView.enable(mode: isEnable ? .drawing : .default)
            
            // Применяем инструмент из ToolStateManager
            if isEnable, let toolStateManager = toolStateManager {
                overlayView.toolStateManager = toolStateManager
                toolStateManager.applyTool(to: overlayView.canvasView)
                
                // Делаем canvas первым responder только для текущей страницы
                // (чтобы избежать конфликтов с несколькими first responder)
                if pdfPage === currentPage {
                    overlayView.canvasView.becomeFirstResponder()
                }
            } else {
                // Убираем first responder только с текущей страницы
                if pdfPage === currentPage {
                    overlayView.canvasView.resignFirstResponder()
                }
            }
        }
    }
    
    /// Сбрасывает состояние рисования.
    /// Необходимо вызывать перед загрузкой нового документа или перезагрузкой текущего.
    func resetDrawingState() {
        // Проходимся по всем активным overlay view
        overlay.pageToViewMapping.values.forEach { view in
            view.canvasView.resignFirstResponder()
        }
        
        // Очищаем кэш
        overlay.pageToViewMapping.removeAll()
    }
    
    /// Обновляет состояние рисования для всех видимых страниц.
    /// Вызывается при скролле для активации/деактивации canvas на новых видимых страницах.
    func updateDrawingStateForVisiblePages() {
        guard drawingEnabled else { return }
        
        let visiblePages = getVisiblePages()
        
        for pdfPage in visiblePages {
            guard let overlayView = overlay.pageToViewMapping[pdfPage] else { continue }
            
            // Активируем рисование для видимых страниц
            overlayView.enable(mode: .drawing)
            
            if let toolStateManager = toolStateManager {
                overlayView.toolStateManager = toolStateManager
                toolStateManager.applyTool(to: overlayView.canvasView)
            }
        }
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
        
        // ВАЖНО: Сохраняем все изменения перед сменой страницы
        overlay.saveAllDrawings()
        
        currentPageIndex = index
        
        // Обновляем состояние рисования для всех видимых страниц
        updateDrawingStateForVisiblePages()
    }
    
    /// Сохраняет изменения при начале скролла (дополнительная защита).
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Сохраняем изменения перед началом скролла
        overlay.saveAllDrawings()
    }
    
    /// Обновляет состояние при скролле (для плавной активации новых страниц).
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Обновляем состояние рисования для всех видимых страниц при скролле
        // Это позволяет активировать canvas на страницах, которые становятся видимыми
        if drawingEnabled {
            updateDrawingStateForVisiblePages()
        }
    }
}
