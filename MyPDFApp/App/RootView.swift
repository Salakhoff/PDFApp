import SwiftUI

struct RootView: View {
    @State private var viewModel = PDFListViewModel()

    var body: some View {
        PDFListView(viewModel: viewModel)
    }
}
