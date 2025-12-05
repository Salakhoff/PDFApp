import SwiftUI
import PDFKit

/// Обёртка над PDFDocumentView + PDFThumbnailView.
/// Внутри создаёт контейнер UIView, слева показывает миниатюры (если включены),
/// справа — основной PDFView.
struct PDFKitViewRepresentable: UIViewRepresentable {

    // MARK: - Properties

    /// Обязательный URL PDF-документа для загрузки.
    let pdfURL: URL

    /// Флаг режима рисования: true = рисование включено, false = обычный просмотр.
    let drawingEnabled: Bool

    /// Коллбек, вызываемый после создания PDFView, чтобы передать его во ViewModel.
    let onPDFViewCreated: (PDFDocumentView) -> Void

    // MARK: - Internal UIView контейнер

    /// Контейнер, внутри которого живут PDFView и PDFThumbnailView.
    final class ContainerView: UIView {

        let pdfView: PDFDocumentView = {
            let view = PDFDocumentView(frame: .zero)
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupViews()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
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
    }

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> ContainerView {
        let container = ContainerView(frame: .zero)

        // Настраиваем PDFView.
        container.pdfView.loadPDF(url: pdfURL)

        // Передаём PDFView во ViewModel.
        onPDFViewCreated(container.pdfView)

        return container
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        // Обновляем режим рисования.
        uiView.pdfView.drawing(isEnable: drawingEnabled)
    }
}
