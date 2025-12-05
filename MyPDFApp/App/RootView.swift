import SwiftUI

struct RootView: View {
    @State private var viewModel: PDFListViewModel

    init() {
        let config = SupabaseConfiguration.live
        
        let storageService = config.makeStorageService()
        
        _viewModel = State(initialValue: PDFListViewModel(storageService: storageService))
    }

    var body: some View {
        PDFListView(viewModel: viewModel)
    }
}
