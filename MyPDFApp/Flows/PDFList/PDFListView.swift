import SwiftUI

struct PDFListView: View {
    @Bindable var viewModel: PDFListViewModel
    
    /// Флаг показа Document Picker'а.
    @State private var isDocumentPickerPresented = false
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.documents.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "Нет PDF-файлов",
                        systemImage: "doc.text",
                        description: Text("Нажмите +, чтобы выбрать PDF или обновите из бека.")
                    )
                } else {
                    List {
                        ForEach(viewModel.documents) { item in
                            NavigationLink(item.name) {
                                PDFEditorView(
                                    viewModel: .init(pdfItem: item) {
                                        Task { await viewModel.loadDocuments() }
                                    }
                                )
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let item = viewModel.documents[index]
                                Task {
                                    await viewModel.deleteDocument(item)
                                }
                            }
                        }
                    }
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .navigationTitle("PDF")
            .toolbar {
                // Кнопка «обновить с бека»
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task {
                            await viewModel.syncFromBackend()
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                
                // Кнопка «добавить локальный PDF»
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isDocumentPickerPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task {
            await viewModel.loadDocuments()
        }
        .sheet(isPresented: $isDocumentPickerPresented) {
            PDFDocumentPickerView { pickedURL in
                Task { @MainActor in
                    await viewModel.importDocument(from: pickedURL)
                    isDocumentPickerPresented = false
                }
            }
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
