import Foundation

@MainActor
@Observable
final class PDFListViewModel {
    
    // MARK: Public Properties
    
    /// Текущий список PDF-документов.
    var documents: [PDFItem] = []
    
    /// Идёт ли сейчас загрузка документов.
    var isLoading: Bool = false
    
    /// Сообщение об ошибке загрузки
    var loadErrorMessage: String?
    
    // MARK: Public API
    
    /// Асинхронно загружает PDF из каталога Documents.
    /// В случае пустого списка подставляет моковые данные.
    func loadDocuments() async {
        isLoading = true
        loadErrorMessage = nil
        documents = []
        
        do {
            // Тяжёлую файловую операцию выполняем в фоновой задаче.
            let loadedDocuments = try await Task.detached(priority: .userInitiated) { () throws -> [PDFItem] in
                let fileManager = FileManager.default
                guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw NSError(domain: "PDFListViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить каталог Documents"])
                }
                
                let files = try fileManager.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)
                let pdfs = files.filter { $0.pathExtension.lowercased() == "pdf" }
                
                return pdfs.map {
                    PDFItem(id: UUID(), name: $0.deletingPathExtension().lastPathComponent, url: $0)
                }
            }.value
            
            documents = loadedDocuments
        } catch {
            loadErrorMessage = error.localizedDescription
            documents = []
        }
        
        if documents.isEmpty && loadErrorMessage == nil {
            loadMockDocuments()
        }
        
        isLoading = false
    }
    
    /// Подставляет встроенный пример PDF, чтобы показать интерфейс без пользовательских файлов.
    func loadMockDocuments() {
        if let sampleURL = Bundle.main.url(forResource: "sample", withExtension: "pdf") {
            documents = [
                PDFItem(id: UUID(), name: "Пример PDF", url: sampleURL)
            ]
        }
    }
}
