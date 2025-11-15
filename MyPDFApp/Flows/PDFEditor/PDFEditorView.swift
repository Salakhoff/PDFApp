import SwiftUI

struct PDFEditorView: View {
    @Bindable var viewModel: PDFEditorViewModel

    var body: some View {
        VStack(spacing: 16) {
            PDFKitViewRepresentable(
                pdfURL: viewModel.pdfItem.url,
                drawingEnabled: viewModel.drawingEnabled,
                onPDFViewCreated: { pdfView in
                    viewModel.configurePDFView(pdfView)
                }
            )

            HStack {
                Button(viewModel.drawingEnabled ? "Завершить рисование" : "Рисовать") {
                    viewModel.toggleDrawing()
                }

                Spacer()

                Button(viewModel.isSaving ? "Сохранение..." : "Сохранить") {
                    Task {
                        await viewModel.save()
                    }
                }
                .disabled(viewModel.isSaving)
            }
            .padding(.horizontal)
        }
        .navigationTitle(viewModel.pdfItem.name)
        .navigationBarTitleDisplayMode(.inline)
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
