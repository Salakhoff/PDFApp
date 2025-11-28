import Foundation
import Supabase

// DTO для документа на сервере
struct RemotePDFDocument {
    /// Идентификатор документа (совпадает с базовым именем файла без расширения)
    let id: String
    /// Путь к PDF-файлу в бакете
    let pdfPath: String
    /// Путь к JSON с аннотациями в бакете (если есть)
    let jsonPath: String?
}

// MARK: - Протокол сервиса

/// Сервис для работы с Supabase Storage (CRUD для PDF + JSON-аннотаций).
protocol SupabaseStorageServicing {
    /// CREATE / UPDATE: загружает (или перезаписывает) PDF и JSON в бакет.
    func uploadDocument(
        id: String,
        localPDF: URL,
        annotationsJSON: Data?
    ) async throws -> RemotePDFDocument
    
    /// READ - список всех документов в бакете.
    func listDocuments() async throws -> [RemotePDFDocument]
    
    /// READ - загрузка одного документа (PDF + JSON) по id.
    func downloadDocument(
        id: String
    ) async throws -> (localPDF: URL, annotationsJSON: Data?)
    
    /// DELETE - удаление PDF и JSON из бакета.
    func deleteDocument(id: String) async throws
}

// MARK: - Реализация сервиса

/// Реализация сервиса для работы с Supabase Storage.
final class SupabaseStorageService: SupabaseStorageServicing {
    
    static let shared: SupabaseStorageServicing = {
        // ⚠️ Подставьте реальные URL и ключ
        let url = URL(string: "https://gehfgutaeanwuohwfbqb.supabase.co")!
        let key = "sb_publishable_Th27b8D-GUsU4jTIhXr1Gg_rAGPIGiG"
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        let service = SupabaseStorageService(client: client)
        print("🟢 SupabaseStorageService.shared создан. URL=\(url.absoluteString)")
        return service
    }()
    
    // MARK: - Private Properties
    
    /// Клиент Supabase, сконфигурированный в AppDelegate/где-то выше.
    private let client: SupabaseClient
    
    /// Имя бакета, где хранятся PDF и JSON.
    private let bucket = "pdf_documents"
    
    // MARK: - Init
    
    /// Инициализатор, принимает уже сконфигурированный SupabaseClient.
    init(client: SupabaseClient) {
        self.client = client
        print("🟢 SupabaseStorageService init. Bucket='\(bucket)'")
    }
    
    // MARK: - Public API
    
    /// Загружает (или перезаписывает) PDF и JSON в бакет.
    func uploadDocument(
        id: String,
        localPDF: URL,
        annotationsJSON: Data?
    ) async throws -> RemotePDFDocument {
        let pdfPath = "\(id).pdf"
        let jsonPath = "\(id).json"
        
        print("⬆️ uploadDocument: bucket='\(bucket)', pdfPath='\(pdfPath)', jsonPath='\(jsonPath)'")
        
        let pdfData = try Data(contentsOf: localPDF)
        
        do {
            _ = try await client.storage
                .from(bucket)
                .upload(
                    path: pdfPath,
                    file: pdfData,
                    options: FileOptions(upsert: true)
                )
            print("✅ PDF загружен в Supabase: \(pdfPath)")
        } catch {
            print("❌ Ошибка upload PDF: \(error)")
            throw error
        }
        
        if let data = annotationsJSON {
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                print("📊 Аннотаций для отправки: \(arr.count) страниц")
            } else {
                print("📊 Аннотаций для отправки: формат не массив")
            }
        }
        
        if let data = annotationsJSON {
            do {
                _ = try await client.storage
                    .from(bucket)
                    .upload(
                        path: jsonPath,
                        file: data,
                        options: FileOptions(upsert: true)
                    )
                print("✅ JSON загружен в Supabase: \(jsonPath)")
            } catch {
                print("❌ Ошибка upload JSON: \(error)")
                throw error
            }
        }
        
        return RemotePDFDocument(
            id: id,
            pdfPath: pdfPath,
            jsonPath: annotationsJSON == nil ? nil : jsonPath
        )
    }
    
    /// Возвращает список всех документов (группируем .pdf и .json по id).
    func listDocuments() async throws -> [RemotePDFDocument] {
            print("📥 listDocuments: bucket='\(bucket)'")
            let objects = try await client.storage
                .from(bucket)
                .list(path: "")
            print("📦 Получено объектов из Supabase: \(objects.count)")
        
        var map: [String: (pdf: String?, json: String?)] = [:]
        
        for object in objects {
            let name = object.name // "abc123.pdf" / "abc123.json"
            let nsName = name as NSString
            let id = nsName.deletingPathExtension
            let ext = nsName.pathExtension.lowercased()
            
            var entry = map[id] ?? (pdf: nil, json: nil)
            if ext == "pdf" {
                entry.pdf = name
            } else if ext == "json" {
                entry.json = name
            }
            map[id] = entry
        }
        
        return map.compactMap { (id, paths) in
            guard let pdfPath = paths.pdf else { return nil }
            return RemotePDFDocument(id: id, pdfPath: pdfPath, jsonPath: paths.json)
        }
    }
    
    /// Скачивает PDF и JSON по id, сохраняет PDF во временный файл и возвращает его URL + JSON.
    func downloadDocument(
        id: String
    ) async throws -> (localPDF: URL, annotationsJSON: Data?) {
        let pdfPath = "\(id).pdf"
        let jsonPath = "\(id).json"
        
        // ✅ download(path:)
        let pdfData = try await client.storage
            .from(bucket)
            .download(path: pdfPath)
        
        let jsonData = try? await client.storage
            .from(bucket)
            .download(path: jsonPath)
        
        // Сохраняем PDF во временный файл
        let tempDir = FileManager.default.temporaryDirectory
        let localURL = tempDir.appendingPathComponent(pdfPath)
        try pdfData.write(to: localURL) // без .atomic, он тут не обязателен
        
        return (localPDF: localURL, annotationsJSON: jsonData)
    }
    
    /// Удаляет PDF и JSON по id из бакета.
    func deleteDocument(id: String) async throws {
        let paths = ["\(id).pdf", "\(id).json"]
        // ✅ remove(paths:)
        _ = try await client.storage
            .from(bucket)
            .remove(paths: paths)
    }
}
