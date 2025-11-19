import Foundation

@MainActor
@Observable
final class PDFEditorViewModel {
    
    // MARK: Public Properties
    
    /// Текущий PDF-файл для редактирования.
    let pdfItem: PDFItem
    
    /// Признак активного режима рисования.
    var drawingEnabled: Bool = false
    
    /// Идёт ли сейчас сохранение документа
    var isSaving: Bool = false
    
    /// Сообщение об ошибке сохранения
    var saveErrorMessage: String?
    
    /// Флаг успешного сохранения
    var showSaveSuccess: Bool = false
    
    // MARK: Private Properties
    
    /// Конкретный PDFView, с которым работает редактор.
    private var pdfView: PDFDocumentView?
    
    /// Коллбек после успешного сохранения файла
    var onSave: (() -> Void)?
    
    // MARK: Init
    
    init(pdfItem: PDFItem, onSave: (() -> Void)? = nil) {
        self.pdfItem = pdfItem
        self.onSave = onSave
    }
    
    // MARK: Public API
    
    /// Привязывает созданный `PDFDocumentView`, чтобы управлять режимом рисования и сохранением.
    func configurePDFView(_ pdfView: PDFDocumentView) {
        self.pdfView = pdfView
    }
    
    /// Переключает режим рисования и уведомляет PDF-вью.
    func toggleDrawing() {
        drawingEnabled.toggle()
        pdfView?.drawing(isEnable: drawingEnabled)
    }
    
    /// Сохраняет текущий документ в каталоге пользователя.
    func save() async {
        guard let destinationFolder = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            print("❌ Не удалось получить путь сохранения")
            return
        }

        let fileName = "\(pdfItem.name)-edited.pdf"

        guard let pdfView else {
            print("❌ PDFView не сконфигурирован")
            return
        }

        isSaving = true
        saveErrorMessage = nil
        showSaveSuccess = false

        do {
            try await pdfView.saveTo(url: destinationFolder, fileName: fileName)
            showSaveSuccess = true
            onSave?()
        } catch {
            saveErrorMessage = error.localizedDescription
            print("❌ Ошибка сохранения PDF: \(error)")
        }

        isSaving = false
    }
    
    /// Отменяет последний штрих рисования через текущий PDFView.
    func undo() {
        pdfView?.undoDrawing()
    }

    /// Повторяет отменённый штрих рисования через текущий PDFView.
    func redo() {
        pdfView?.redoDrawing()
    }
}
