import SwiftUI

struct PDFEditorView: View {
    @Bindable var viewModel: PDFEditorViewModel
    
    var body: some View {
        GeometryReader { geometry in
            let overlayWidth = viewModel.showThumbnails ? min(geometry.size.width * 0.3, 200) : 0

            ZStack(alignment: .topLeading) {
                PDFKitViewRepresentable(
                    pdfURL: viewModel.pdfItem.url,
                    drawingEnabled: viewModel.drawingEnabled,
                    onPDFViewCreated: { pdfView in
                        viewModel.configurePDFView(pdfView)
                    }
                )

                if viewModel.drawingEnabled {
                    VStack {
                        Spacer()
                        CustomToolPalette(
                            tool: viewModel.toolStateManager.currentTool,
                            isUsingPencil: .constant(false),
                            onToolChanged: {
                                viewModel.pdfView?.updateToolForAllCanvases()
                            }
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }

                if viewModel.showThumbnails {
                    thumbnailOverlay(geometry: geometry, overlayWidth: overlayWidth)
                }

                pageCounterButton(overlayWidth: overlayWidth)
                    .zIndex(1) // чтобы быть поверх overlay
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
    }
    
    // MARK: - Thumbnail Overlay
    
    /// Overlay с миниатюрами страниц PDF.
    private func thumbnailOverlay(geometry: GeometryProxy, overlayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            PDFThumbnailView(
                pdfDocument: viewModel.pdfDocumentForThumbnails,
                currentPageIndex: viewModel.currentPageIndex,
                onPageSelected: { index in
                    viewModel.goToPage(at: index)
                }
            )
            .frame(width: overlayWidth)
            .background(
                Color.white.opacity(0.95)
                    .ignoresSafeArea(edges: .leading)
            )
            .transition(.move(edge: .leading).combined(with: .opacity))
               .animation(.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0.1),
                          value: viewModel.showThumbnails)
        }

    }
    
    // MARK: - Page Counter Button
    
    /// Кнопка с индикатором текущей страницы (формат "X/Y") в левом верхнем углу.
    /// Располагается правее thumbnailOverlay, если он показан.
    private func pageCounterButton(overlayWidth: CGFloat) -> some View {
        let totalPages = viewModel.totalPagesCount
        let pageText = totalPages > 0
        ? "\(viewModel.currentPageIndex + 1)/\(totalPages)"
        : "—"
        
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0.1)) {
                viewModel.toggleThumbnails()
            }
        } label: {
            HStack {
                Image(systemName: "sidebar.left")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                
                Text(pageText)
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white)
            .clipShape(.capsule)
            .shadow(color: Color.black, radius: 4, x: 2, y: 2)
        }
        .padding(.leading, overlayWidth + 8)
        .padding(.top, 8)
    }
    
    // MARK: - Toolbars
    
    @ToolbarContentBuilder
    private var leadingToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            // Убрали кнопку показа миниатюр из toolbar
            
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
