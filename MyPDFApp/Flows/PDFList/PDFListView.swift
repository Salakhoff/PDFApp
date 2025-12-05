import SwiftUI

struct PDFListView: View {
    @Bindable var viewModel: PDFListViewModel
    
    @State private var isDocumentPickerPresented = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                content
                
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .navigationTitle("PDF")
            .toolbar {
                leadingToolbar
                trailingToolbar
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

// MARK: - Content

private extension PDFListView {
    
    @ViewBuilder
    var content: some View {
        if viewModel.documents.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            documentList
        }
    }
    
    var emptyState: some View {
        ContentUnavailableView(
            "Нет PDF-файлов",
            systemImage: "doc.text",
            description: Text("Нажмите +, чтобы выбрать PDF или обновите из бэка.")
        )
    }
    
    var documentList: some View {
        List {
            ForEach(viewModel.documents) { item in
                NavigationLink(item.name) {
                    editorView(for: item)
                }
            }
            .onDelete(perform: delete)
        }
    }
    
    func editorView(for item: PDFItem) -> some View {
        PDFEditorView(
            viewModel: PDFEditorViewModel(
                pdfItem: item,
                onSave: {
                    Task { @MainActor in
                        await viewModel.loadDocuments()
                    }
                },
                storageService: viewModel.storageService
            )
        )
    }
    
    func delete(at indexSet: IndexSet) {
        for index in indexSet {
            let item = viewModel.documents[index]
            Task { @MainActor in
                await viewModel.deleteDocument(item)
            }
        }
    }
}

// MARK: - Toolbars

private extension PDFListView {
    
    @ToolbarContentBuilder
    var leadingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { @MainActor in
                    await viewModel.syncFromBackend()
                }
            } label: {
                Image(systemName: "arrow.down.circle")
            }
        }
    }
    
    @ToolbarContentBuilder
    var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isDocumentPickerPresented = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}
