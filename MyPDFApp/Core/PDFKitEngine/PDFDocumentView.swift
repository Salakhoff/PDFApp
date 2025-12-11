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
    
    /// Коллбек при загрузке документа: totalPages, currentIndex
    var onDocumentLoaded: ((Int, Int) -> Void)?
    
    /// Коллбек при смене страницы
    var onPageIndexChanged: ((Int) -> Void)?
    
    /// Таймер для периодической проверки текущей страницы (fallback механизм).
    private var pageCheckTimer: Timer?
    
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
        
        // 0. Синхронизируем все рисунки из canvas в страницы перед сохранением
        overlay.saveAllDrawings()
        
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
        overlay.saveAllDrawings()
        return pdfDocument?.exportAnnotationsAsJSON()
    }
    
    /// Плавно переходит к указанной странице документа.
    /// - Parameter index: Индекс страницы (начиная с 0).
    func goToPage(at index: Int) {
        guard let document = document,
              index >= 0,
              index < document.pageCount,
              let page = document.page(at: index) else {
            return
        }
        
        // Плавная анимация перехода к странице
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            self.go(to: page)
        } completion: { _ in
            // Обновляем индекс текущей страницы после завершения анимации
            self.updateCurrentPageIndex()
        }
    }
    
    /// Возвращает PDFDocument для генерации миниатюр.
    var pdfDocumentForThumbnails: PDFDocument? {
        document
    }
    
    /// Определяет текущую страницу как страницу с максимальной видимой площадью.
    func updateCurrentPageIndex() {
        guard let document = document else { return }
        
        let visibleRect = bounds
        var bestIndex = currentPageIndex
        var maxVisibleArea: CGFloat = 0
        
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            
            // Берём cropBox (или mediaBox — если так точнее для вашего документа)
            let pageRect = convert(page.bounds(for: .cropBox), from: page)
            
            let intersection = visibleRect.intersection(pageRect)
            let area = max(0, intersection.width) * max(0, intersection.height)
            
            if area > maxVisibleArea {
                maxVisibleArea = area
                bestIndex = index
            }
        }
        
        // Обновляем только при реальной смене страницы
        if maxVisibleArea > 0, bestIndex != currentPageIndex {
            currentPageIndex = bestIndex
            onPageIndexChanged?(bestIndex)
        }
    }
    
    /// Обрабатывает смену страницы от PDFView (NotificationCenter).
    @objc private func handlePageChanged(_ notification: Notification) {
        updateCurrentPageIndex()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        pageCheckTimer?.invalidate()
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
        
        // Подписываемся на уведомления о смене страницы
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePageChanged),
            name: .PDFViewPageChanged,
            object: self
        )
        
        // Делегат для событий скролла, чтобы обновлять currentPageIndex
        privateScrollView?.delegate = self
        
        // Запускаем таймер для периодической проверки текущей страницы (каждые 0.1 секунды)
        pageCheckTimer?.invalidate()
        pageCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateCurrentPageIndex()
        }
        
        // Важно: добавляем таймер в RunLoop для работы в режиме скролла
        if let timer = pageCheckTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
        print("✅ Таймер проверки страниц запущен")
        
        let totalPages = document?.pageCount ?? 0
        updateCurrentPageIndex()
        onDocumentLoaded?(totalPages, currentPageIndex)
        
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
        // Останавливаем таймер проверки страниц
        pageCheckTimer?.invalidate()
        pageCheckTimer = nil
        
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
        // ВАЖНО: Сохраняем все изменения перед сменой страницы
        overlay.saveAllDrawings()
        
        // Обновляем индекс текущей страницы
        updateCurrentPageIndex()
        
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
        
        // Обновляем индекс текущей страницы при скролле
        updateCurrentPageIndex()
        
        // Обновляем состояние рисования для всех видимых страниц при скролле
        // Это позволяет активировать canvas на страницах, которые становятся видимыми
        if drawingEnabled {
            updateDrawingStateForVisiblePages()
        }
    }
}
