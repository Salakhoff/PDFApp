import SwiftUI

struct PDFListView: View {
    @Bindable var viewModel: PDFListViewModel
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.documents.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "Нет PDF-файлов",
                        systemImage: "doc.text",
                        description: Text("Добавьте PDF в каталог Documents или используйте встроенный пример.")
                    )
                } else {
                    List(viewModel.documents) { item in
                        NavigationLink(item.name) {
                            PDFEditorView(
                                viewModel: .init(pdfItem: item) {
                                    Task {
                                        await viewModel.loadDocuments()
                                    }
                                }
                            )
                        }
                    }
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .navigationTitle("PDF")
        }
        .task {
            await viewModel.loadDocuments()
        }
        .alert(
            "Ошибка загрузки",
            isPresented: Binding(
                get: { viewModel.loadErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.loadErrorMessage = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) { }
            },
            message: {
                Text(viewModel.loadErrorMessage ?? "Неизвестная ошибка")
            }
        )
    }
}
