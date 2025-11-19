import SwiftUI

/// Экран редактирования PDF.
/// Показывает документ и кнопки управления режимом рисования/сохранением.
struct PDFEditorView: View {
    @Bindable var viewModel: PDFEditorViewModel

    var body: some View {
        PDFKitViewRepresentable(
            pdfURL: viewModel.pdfItem.url,
            drawingEnabled: viewModel.drawingEnabled,
            onPDFViewCreated: { pdfView in
                viewModel.configurePDFView(pdfView)
            }
        )
        .navigationTitle(viewModel.pdfItem.name)
        .navigationBarTitleDisplayMode(.inline)
        // Кнопки в NavigationBar
        .toolbar {
            // Левая часть: Undo / Redo (только в режиме рисования)
            ToolbarItemGroup(placement: .navigationBarLeading) {
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

            // Правая часть: переключатель рисования + сохранение
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    viewModel.toggleDrawing()
                } label: {
                    Image(systemName: viewModel.drawingEnabled ? "pencil.slash" : "pencil.tip")
                }

                Button {
                    Task {
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
        // Алерт ошибки сохранения
        .alert(
            "Ошибка сохранения",
            isPresented: Binding(
                get: { viewModel.saveErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.saveErrorMessage = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) { }
            },
            message: {
                Text(viewModel.saveErrorMessage ?? "Неизвестная ошибка")
            }
        )
        // Алерт успешного сохранения
        .alert(
            "Готово",
            isPresented: Binding(
                get: { viewModel.showSaveSuccess },
                set: { newValue in
                    if !newValue {
                        viewModel.showSaveSuccess = false
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) { }
            },
            message: {
                Text("PDF успешно сохранён.")
            }
        )
    }
}
