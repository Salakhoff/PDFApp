import Foundation

@MainActor
@Observable
final class PDFListViewModel {
    
    // MARK: - Public Properties
    
    var documents: [PDFItem] = []
    var isLoading: Bool = false
    var loadErrorMessage: String?
    
    // MARK: - Dependencies
    
    /// Сервис Supabase Storage для синхронизации PDF и аннотаций.
    private let storageService: SupabaseStorageServicing = SupabaseStorageService.shared
    
    // MARK: - Public API
    
    /// Асинхронно загружает PDF из каталога Documents.
    func loadDocuments() async {
        isLoading = true
        loadErrorMessage = nil
        documents = []
        
        do {
            let loadedDocuments = try await Task.detached(priority: .userInitiated) { () throws -> [PDFItem] in
                let fileManager = FileManager.default
                guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw NSError(
                        domain: "PDFListViewModel",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Не удалось получить каталог Documents"]
                    )
                }
                
                let files = try fileManager.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)
                let pdfs = files.filter { $0.pathExtension.lowercased() == "pdf" }
                
                return pdfs.map {
                    PDFItem(
                        id: UUID(),
                        name: $0.deletingPathExtension().lastPathComponent,
                        url: $0
                    )
                }
            }.value
            
            documents = loadedDocuments
        } catch {
            loadErrorMessage = error.localizedDescription
            documents = []
        }
        
        isLoading = false
    }
    
    /// Импортирует выбранный через UIDocumentPicker PDF в каталог Documents
    /// и обновляет список документов.
    func importDocument(from pickedURL: URL) async {
        do {
            let fileManager = FileManager.default
            guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw NSError(
                    domain: "PDFListViewModel",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Не удалось получить каталог Documents"]
                )
            }
            
            let destinationURL = docsURL.appendingPathComponent(pickedURL.lastPathComponent)
            
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.copyItem(at: pickedURL, to: destinationURL)
            
            await loadDocuments()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }
    
    /// Синхронизирует локальные PDF + JSON с Supabase:
    /// скачивает все документы из бакета, сохраняет в Documents и обновляет список.
    func syncFromBackend() async {
        isLoading = true
        loadErrorMessage = nil
        
        do {
            let remoteDocs = try await storageService.listDocuments()
            
            let fileManager = FileManager.default
            guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw NSError(
                    domain: "PDFListViewModel",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Не удалось получить каталог Documents"]
                )
            }
            
            for remote in remoteDocs {
                // 1. Скачиваем PDF + JSON
                let result = try await storageService.downloadDocument(id: remote.id)
                
                // 2. Сохраняем / перезаписываем PDF
                let pdfFileName = "\(remote.id).pdf"
                let pdfURL = docsURL.appendingPathComponent(pdfFileName)
                
                if fileManager.fileExists(atPath: pdfURL.path) {
                    try fileManager.removeItem(at: pdfURL)
                }
                try fileManager.copyItem(at: result.localPDF, to: pdfURL)
                
                // 3. Сохраняем / перезаписываем JSON (если есть)
                if let data = result.annotationsJSON {
                    let jsonFileName = "\(remote.id).json"
                    let jsonURL = docsURL.appendingPathComponent(jsonFileName)
                    
                    if fileManager.fileExists(atPath: jsonURL.path) {
                        try fileManager.removeItem(at: jsonURL)
                    }
                    
                    try data.write(to: jsonURL)
                }
            }
            
            // 4. Обновляем список локальных документов
            await loadDocuments()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// Удаляет документ и связанные с ним аннотации локально.
    /// - Parameter item: PDF документ для удаления
    func deleteDocument(_ item: PDFItem) async {    
        do {
            let fileManager = FileManager.default
            
            // 1. Удаляем PDF файл
            if fileManager.fileExists(atPath: item.url.path) {
                try fileManager.removeItem(at: item.url)
            }
            
            // 2. Удаляем JSON файл с аннотациями (если существует)
            let jsonFileName = item.url.deletingPathExtension().lastPathComponent + ".json"
            let jsonURL = item.url.deletingLastPathComponent().appendingPathComponent(jsonFileName)
            
            if fileManager.fileExists(atPath: jsonURL.path) {
                try fileManager.removeItem(at: jsonURL)
            }
            
            // 3. Обновляем список документов
            await loadDocuments()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }
}
