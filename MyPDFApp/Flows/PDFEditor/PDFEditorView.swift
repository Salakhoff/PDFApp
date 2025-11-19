import SwiftUI

/// Экран редактирования PDF.
/// Показывает документ и кнопки управления режимом рисования/сохранением.
struct PDFEditorView: View {
    @Bindable var viewModel: PDFEditorViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            PDFKitViewRepresentable(
                pdfURL: viewModel.pdfItem.url,
                drawingEnabled: viewModel.drawingEnabled,
                showThumbnails: viewModel.thumbnailVisible,
                onPDFViewCreated: { pdfView in
                    viewModel.configurePDFView(pdfView)
                }
            )

            // Круглая кнопка показа/скрытия миниатюр в левом верхнем углу поверх PDF.
            Button {
                viewModel.toggleThumbnails()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.85))
                    )
                    .shadow(radius: 4)
            }
            .padding()
        }
        .navigationTitle(viewModel.pdfItem.name)
        .navigationBarTitleDisplayMode(.inline)
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

            // Правая часть: рисование + сохранение
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
