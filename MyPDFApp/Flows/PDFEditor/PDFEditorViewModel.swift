import Foundation
import PDFKit

@MainActor
@Observable
final class PDFEditorViewModel {
    
    // MARK: Alert state
    
    enum SaveAlert: Identifiable, Equatable {
        case success
        case error(message: String)
        
        var id: String {
            switch self {
            case .success: "success"
            case .error(let message): "error-\(message)"
            }
        }
        
        var title: String {
            switch self {
            case .success: "Готово"
            case .error: "Ошибка сохранения"
            }
        }
        
        var messageText: String {
            switch self {
            case .success: "PDF успешно сохранён."
            case .error(let message): message
            }
        }
    }
    
    // MARK: Public properties
    
    /// Текущий PDF-файл для редактирования.
    let pdfItem: PDFItem
    
    /// Признак активного режима рисования.
    var drawingEnabled = false
    
    /// Идёт ли сейчас сохранение документа.
    var isSaving = false
    
    /// Текущее состояние алерта сохранения.
    var saveAlert: SaveAlert?
    
    /// Коллбек после успешного сохранения файла.
    var onSave: (@MainActor () -> Void)?
    
    /// Менеджер состояния инструментов рисования.
    let toolStateManager = ToolStateManager()
    
    // MARK: - Private properties
    
    /// Конкретный PDFView, с которым работает редактор.
    var pdfView: PDFDocumentView?
    
    /// Флаг отображения thumbnail view с миниатюрами страниц.
    var showThumbnails = false
    
    /// Сервис Supabase Storage для синхронизации PDF и аннотаций.
    private let storageService: SupabaseStorageServicing
    
    /// Файловый менеджер (можно подменить в тестах).
    private let fileManager: FileManager
    
    /// Текущая страница (для SwiftUI)
    var currentPageIndex: Int = 0
    
    /// Кол-во страниц (для SwiftUI)
    var totalPagesCount: Int = 0
    
    // MARK: - Init
    
    init(
        pdfItem: PDFItem,
        onSave: (@MainActor () -> Void)? = nil,
        storageService: SupabaseStorageServicing,
        fileManager: FileManager = .default
    ) {
        self.pdfItem = pdfItem
        self.onSave = onSave
        self.storageService = storageService
        self.fileManager = fileManager
    }
    
    // MARK: Public API
    
    /// Привязывает созданный `PDFDocumentView`, чтобы управлять режимом рисования и сохранением.
    func configurePDFView(_ pdfView: PDFDocumentView) {
        self.pdfView = pdfView
        pdfView.toolStateManager = toolStateManager
        
        pdfView.onDocumentLoaded = { [weak self] totalPages, currentIndex in
            print("📥 onDocumentLoaded: totalPages=\(totalPages), currentIndex=\(currentIndex)")
            self?.totalPagesCount = totalPages
            self?.currentPageIndex = currentIndex
        }
        
        pdfView.onPageIndexChanged = { [weak self] index in
            print("📥 onPageIndexChanged вызван с индексом: \(index)")
            self?.currentPageIndex = index
            print("📥 currentPageIndex в ViewModel теперь: \(self?.currentPageIndex ?? -1)")
        }
    }
    
    /// Переключает режим рисования и уведомляет PDF-вью.
    func toggleDrawing() {
        drawingEnabled.toggle()
        pdfView?.drawing(isEnable: drawingEnabled)
    }
    
    func save() async {
        guard !isSaving else { return }
        
        // Путь сохранения.
        guard let destinationFolder = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            saveAlert = .error(message: "Не удалось получить путь сохранения документа.")
            return
        }
        
        // PDFView должен быть уже сконфигурирован.
        guard let pdfView else {
            saveAlert = .error(message: "Документ ещё не загружен. Повторите попытку позже.")
            return
        }
        
        isSaving = true
        saveAlert = nil
        defer { isSaving = false }
        
        let fileName = pdfItem.url.lastPathComponent
        let localPDFURL = destinationFolder.appendingPathComponent(fileName)
        let remoteId = pdfItem.url.deletingPathExtension().lastPathComponent
        
        do {
            // 1. Экспорт и локальное сохранение JSON с аннотациями.
            let annotationsJSON = pdfView.exportAnnotationsJSON()
            try saveAnnotationsIfNeeded(
                annotationsJSON,
                to: destinationFolder,
                baseFileName: fileName
            )
            
            // 2. Локальное сохранение PDF.
            try await pdfView.saveTo(url: destinationFolder, fileName: fileName)
            
            // 3. Отправка в Supabase (ошибка не ломает локальное сохранение).
            do {
                _ = try await storageService.uploadDocument(
                    id: remoteId,
                    localPDF: localPDFURL,
                    annotationsJSON: annotationsJSON
                )
            } catch {
                print("⚠️ Ошибка отправки в Supabase: \(error)")
            }
            
            // 4. Успех.
            saveAlert = .success
            onSave?()
            
        } catch {
            saveAlert = .error(message: error.localizedDescription)
        }
    }
    
    /// Отменяет последний штрих рисования через текущий PDFView.
    func undo() {
        pdfView?.undoDrawing()
    }
    
    /// Повторяет отменённый штрих рисования через текущий PDFView.
    func redo() {
        pdfView?.redoDrawing()
    }
    
    /// Переключает отображение thumbnail view с миниатюрами страниц.
    func toggleThumbnails() {
        showThumbnails.toggle()
    }
    
    /// Переходит к указанной странице в PDF-документе.
    /// - Parameter index: Индекс страницы (начиная с 0).
    func goToPage(at index: Int) {
        pdfView?.goToPage(at: index)
    }
    
    /// Возвращает PDFDocument для генерации миниатюр.
    var pdfDocumentForThumbnails: PDFDocument? {
        pdfView?.pdfDocumentForThumbnails
    }
    
    // MARK: Private
    
    private func saveAnnotationsIfNeeded(
        _ data: Data?,
        to folder: URL,
        baseFileName: String
    ) throws {
        guard let data else { return }
        
        let jsonFileName: String
        if baseFileName.lowercased().hasSuffix(".pdf") {
            jsonFileName = String(baseFileName.dropLast(4)) + ".json"
        } else {
            jsonFileName = baseFileName + ".json"
        }
        
        let jsonURL = folder.appendingPathComponent(jsonFileName)
        try data.write(to: jsonURL)
    }
}
