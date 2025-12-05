import Foundation
import Supabase

struct RemotePDFDocument {
    let id: String
    let pdfPath: String
    let jsonPath: String?
}

protocol SupabaseStorageServicing {
    /// Загружает (или перезаписывает) PDF и JSON в бакет.
    func uploadDocument(
        id: String,
        localPDF: URL,
        annotationsJSON: Data?
    ) async throws -> RemotePDFDocument
    
    /// Список всех документов в бакете.
    func listDocuments() async throws -> [RemotePDFDocument]
    
    /// Загрузка одного документа (PDF + JSON)
    func downloadDocument(
        id: String
    ) async throws -> (localPDF: URL, annotationsJSON: Data?)
    
    /// Удаление PDF и JSON из бакета.
    func deleteDocument(id: String) async throws
}

actor SupabaseStorageService: SupabaseStorageServicing {
    
    // MARK: Private Properties
    
    private let client: SupabaseClient
    private let bucket: String
    
    // MARK: Init
    
    init(client: SupabaseClient, bucket: String) {
        self.client = client
        self.bucket = bucket
    }
    
    // MARK: Public API
    
    func uploadDocument(
        id: String,
        localPDF: URL,
        annotationsJSON: Data?
    ) async throws -> RemotePDFDocument {
        let pdfPath = "\(id).pdf"
        let jsonPath = "\(id).json"
        
        let pdfData = try Data(contentsOf: localPDF)
        
        // Upload PDF
        _ = try await client.storage
            .from(bucket)
            .upload(
                pdfPath,
                data: pdfData,
                options: FileOptions(upsert: true)
            )
        
        // Upload JSON if present
        if let data = annotationsJSON {
            _ = try await client.storage
                .from(bucket)
                .upload(
                    jsonPath,
                    data: data,
                    options: FileOptions(upsert: true)
                )
        }
        
        return RemotePDFDocument(
            id: id,
            pdfPath: pdfPath,
            jsonPath: annotationsJSON == nil ? nil : jsonPath
        )
    }
    
    func listDocuments() async throws -> [RemotePDFDocument] {
        let objects = try await client.storage
            .from(bucket)
            .list(path: "")
        
        var map: [String: (pdf: String?, json: String?)] = [:]
        
        for object in objects {
            let name = object.name
            let nsName = name as NSString
            let id = nsName.deletingPathExtension
            let ext = nsName.pathExtension.lowercased()
            
            var entry = map[id] ?? (pdf: nil, json: nil)
            
            switch ext {
            case "pdf": entry.pdf = name
            case "json": entry.json = name
            default: break
            }
            
            map[id] = entry
        }
        
        return map.compactMap { (id, paths) in
            guard let pdfPath = paths.pdf else { return nil }
            return RemotePDFDocument(
                id: id,
                pdfPath: pdfPath,
                jsonPath: paths.json
            )
        }
    }
    
    func downloadDocument(
        id: String
    ) async throws -> (localPDF: URL, annotationsJSON: Data?) {
        let pdfPath = "\(id).pdf"
        let jsonPath = "\(id).json"
        
        let pdfData = try await client.storage
            .from(bucket)
            .download(path: pdfPath)
        
        let jsonData = try? await client.storage
            .from(bucket)
            .download(path: jsonPath)
        
        let tempDir = FileManager.default.temporaryDirectory
        let localURL = tempDir.appendingPathComponent(pdfPath)
        try pdfData.write(to: localURL)
        
        return (localPDF: localURL, annotationsJSON: jsonData)
    }
    
    func deleteDocument(id: String) async throws {
        let paths = ["\(id).pdf", "\(id).json"]
        _ = try await client.storage
            .from(bucket)
            .remove(paths: paths)
    }
    
}
