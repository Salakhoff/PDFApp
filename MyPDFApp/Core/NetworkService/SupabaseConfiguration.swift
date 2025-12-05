import Foundation
import Supabase

struct SupabaseConfiguration {
    let url: URL
    let key: String
    let bucket: String
    
    static var live: SupabaseConfiguration {
        SupabaseConfiguration(
            url: URL(string: "https://gehfgutaeanwuohwfbqb.supabase.co")!,
            key: "sb_publishable_Th27b8D-GUsU4jTIhXr1Gg_rAGPIGiG",
            bucket: "pdf_documents"
        )
    }
    
    func makeStorageService() -> SupabaseStorageServicing {
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        return SupabaseStorageService(client: client, bucket: bucket)
    }
}
