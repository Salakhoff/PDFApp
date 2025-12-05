import SwiftUI
import PDFKit

struct PDFKitViewRepresentable: UIViewRepresentable {
    
    // MARK: Public properties
    
    /// URL PDF-документа для загрузки.
    let pdfURL: URL
    
    /// Флаг режима рисования: true = рисование включено, false = обычный просмотр.
    let drawingEnabled: Bool
    
    /// Коллбек, вызываемый после создания PDFView, чтобы передать его во ViewModel.
    let onPDFViewCreated: @MainActor (PDFDocumentView) -> Void
    
    // MARK: UIViewRepresentable
    
    func makeUIView(context: Context) -> ContainerView {
        let container = ContainerView()
        container.loadIfNeeded(pdfURL: pdfURL)
        container.pdfView.drawing(isEnable: drawingEnabled)
        
        onPDFViewCreated(container.pdfView)
        
        return container
    }
    
    func updateUIView(_ uiView: ContainerView, context: Context) {
        uiView.loadIfNeeded(pdfURL: pdfURL)
        uiView.pdfView.drawing(isEnable: drawingEnabled)
    }
    
    // MARK: Internal UIView container
    
    final class ContainerView: UIView {
        
        let pdfView: PDFDocumentView = {
            let view = PDFDocumentView(frame: .zero)
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }()
        
        private var currentURL: URL?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            setupViews()
        }
        
        required init?(coder: NSCoder) {
            nil
        }
        
        private func setupViews() {
            addSubview(pdfView)
            
            NSLayoutConstraint.activate([
                pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
                pdfView.topAnchor.constraint(equalTo: topAnchor),
                pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
                pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        
        func loadIfNeeded(pdfURL: URL) {
            guard currentURL != pdfURL else { return }
            currentURL = pdfURL
            pdfView.loadPDF(url: pdfURL)
        }
    }
}
