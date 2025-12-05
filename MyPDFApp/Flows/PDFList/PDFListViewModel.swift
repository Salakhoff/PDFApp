import Foundation

@MainActor
@Observable
final class PDFListViewModel {
    
    // MARK: Public Properties
    
    var documents: [PDFItem] = []
    var isLoading = false
    var loadErrorMessage: String?
    
    // MARK: Dependencies
    
    let storageService: SupabaseStorageServicing
    private let fileManager: FileManager
    
    // MARK: Init
    
    init(
        storageService: SupabaseStorageServicing,
        fileManager: FileManager = .default
    ) {
        self.storageService = storageService
        self.fileManager = fileManager
    }
    
    // MARK: Public API
    
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
    func importDocument(from pickedURL: URL) async {
        do {
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
    func syncFromBackend() async {
        isLoading = true
        loadErrorMessage = nil
        
        do {
            let remoteDocs = try await storageService.listDocuments()
            
            guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw NSError(
                    domain: "PDFListViewModel",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Не удалось получить каталог Documents"]
                )
            }
            
            for remote in remoteDocs {
                let result = try await storageService.downloadDocument(id: remote.id)
                
                let pdfFileName = "\(remote.id).pdf"
                let pdfURL = docsURL.appendingPathComponent(pdfFileName)
                
                if fileManager.fileExists(atPath: pdfURL.path) {
                    try fileManager.removeItem(at: pdfURL)
                }
                try fileManager.copyItem(at: result.localPDF, to: pdfURL)
                
                if let data = result.annotationsJSON {
                    let jsonFileName = "\(remote.id).json"
                    let jsonURL = docsURL.appendingPathComponent(jsonFileName)
                    
                    if fileManager.fileExists(atPath: jsonURL.path) {
                        try fileManager.removeItem(at: jsonURL)
                    }
                    
                    try data.write(to: jsonURL)
                }
            }
            
            await loadDocuments()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// Удаляет документ и связанные с ним аннотации локально.
    func deleteDocument(_ item: PDFItem) async {
        do {
            if fileManager.fileExists(atPath: item.url.path) {
                try fileManager.removeItem(at: item.url)
            }
            
            let jsonFileName = item.url.deletingPathExtension().lastPathComponent + ".json"
            let jsonURL = item.url.deletingLastPathComponent().appendingPathComponent(jsonFileName)
            
            if fileManager.fileExists(atPath: jsonURL.path) {
                try fileManager.removeItem(at: jsonURL)
            }
            
            await loadDocuments()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }
}
