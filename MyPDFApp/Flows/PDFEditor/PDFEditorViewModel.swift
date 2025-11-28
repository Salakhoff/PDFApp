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
    
    /// Видимы ли миниатюры страниц.
    var thumbnailVisible: Bool = false
    
    // MARK: Private Properties
    
    /// Конкретный PDFView, с которым работает редактор.
    private var pdfView: PDFDocumentView?
    
    /// Сервис Supabase Storage для синхронизации PDF и аннотаций.
    private let storageService: SupabaseStorageServicing
    
    /// Коллбек после успешного сохранения файла
    var onSave: (() -> Void)?
    
    // MARK: Init
    
    init(
        pdfItem: PDFItem,
        onSave: (() -> Void)? = nil,
        storageService: SupabaseStorageServicing = SupabaseStorageService.shared
    ) {
        self.pdfItem = pdfItem
        self.onSave = onSave
        self.storageService = storageService
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
    
    func save() async {
        guard let destinationFolder = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            print("❌ Не удалось получить путь сохранения")
            return
        }

        let fileName = pdfItem.url.lastPathComponent

        guard let pdfView else {
            print("❌ PDFView не сконфигурирован")
            return
        }

        isSaving = true
        saveErrorMessage = nil
        showSaveSuccess = false

        do {
            // 1. ❗ Сначала единожды экспортируем аннотации
            let annotationsJSON = pdfView.exportAnnotationsJSON()
            if let data = annotationsJSON,
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                print("📊 Аннотаций для отправки: \(arr.count) страниц")
            }

            // 2. Сохраняем JSON локально рядом с PDF (3.json)
            if let data = annotationsJSON {
                let jsonFileName = fileName.replacingOccurrences(of: ".pdf", with: ".json")
                let jsonURL = destinationFolder.appendingPathComponent(jsonFileName)
                try data.write(to: jsonURL)
                print("✅ JSON аннотаций сохранён: \(jsonFileName)")
            }

            // 3. Локальное сохранение PDF
            try await pdfView.saveTo(url: destinationFolder, fileName: fileName)

            // 4. Готовим путь к локальному PDF
            let localPDF = destinationFolder.appendingPathComponent(fileName)

            // 5. Формируем id для Supabase
            let remoteId = pdfItem.url.deletingPathExtension().lastPathComponent

            // 6. Отправляем PDF + ТОТ ЖЕ JSON в Supabase
            do {
                _ = try await storageService.uploadDocument(
                    id: remoteId,
                    localPDF: localPDF,
                    annotationsJSON: annotationsJSON
                )
                print("✅ Документ отправлен в Supabase с id=\(remoteId)")
            } catch {
                print("⚠️ Ошибка отправки в Supabase: \(error)")
            }

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
    
    /// Переключает видимость панели миниатюр.
    func toggleThumbnails() {
        thumbnailVisible.toggle()
    }
}
