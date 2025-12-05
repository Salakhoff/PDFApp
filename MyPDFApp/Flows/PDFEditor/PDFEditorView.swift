import SwiftUI

struct PDFEditorView: View {
    @Bindable var viewModel: PDFEditorViewModel
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            PDFKitViewRepresentable(
                pdfURL: viewModel.pdfItem.url,
                drawingEnabled: viewModel.drawingEnabled,
                onPDFViewCreated: { pdfView in
                    viewModel.configurePDFView(pdfView)
                }
            )
        }
        .navigationTitle(viewModel.pdfItem.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            leadingToolbar
            trailingToolbar
        }
        .alert(item: $viewModel.saveAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.messageText),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // MARK: - Toolbars
    
    @ToolbarContentBuilder
    private var leadingToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            if viewModel.drawingEnabled {
                Button {
                    viewModel.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                
                Button {
                    viewModel.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                viewModel.toggleDrawing()
            } label: {
                Image(systemName: viewModel.drawingEnabled ? "pencil.slash" : "pencil.tip")
            }
            
            Button {
                Task { @MainActor in
                    await viewModel.save()
                }
            } label: {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .disabled(viewModel.isSaving)
        }
    }
}
