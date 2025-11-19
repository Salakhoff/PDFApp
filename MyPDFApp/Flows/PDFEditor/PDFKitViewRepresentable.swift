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

    /// Показывать ли панель миниатюр слева.
    let showThumbnails: Bool

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

        let thumbnailView: PDFThumbnailView = {
            let view = PDFThumbnailView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.layoutMode = .vertical
            view.thumbnailSize = CGSize(width: 80, height: 80)
            view.backgroundColor = UIColor.systemBackground
            return view
        }()

        private var thumbnailWidthConstraint: NSLayoutConstraint?

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupViews()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupViews() {
            addSubview(thumbnailView)
            addSubview(pdfView)

            // Миниатюры слева, PDFView справа, заполняют всю высоту.
            thumbnailWidthConstraint = thumbnailView.widthAnchor.constraint(equalToConstant: 0)

            NSLayoutConstraint.activate([
                thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
                thumbnailView.topAnchor.constraint(equalTo: topAnchor),
                thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor),
                thumbnailWidthConstraint!,

                pdfView.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor),
                pdfView.topAnchor.constraint(equalTo: topAnchor),
                pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
                pdfView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        /// Управляет видимостью и шириной панели миниатюр.
        func setThumbnailsVisible(_ visible: Bool) {
            thumbnailWidthConstraint?.constant = visible ? 120 : 0
            thumbnailView.isHidden = !visible
            layoutIfNeeded()
        }
    }

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> ContainerView {
        let container = ContainerView(frame: .zero)

        // Настраиваем PDFView.
        container.pdfView.loadPDF(url: pdfURL)

        // Связываем thumbnailView с pdfView — PDFThumbnailView сам синхронизируется с ним.
        container.thumbnailView.pdfView = container.pdfView

        // Начальное состояние панели миниатюр.
        container.setThumbnailsVisible(showThumbnails)

        // Передаём PDFView во ViewModel.
        onPDFViewCreated(container.pdfView)

        return container
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        // Обновляем режим рисования.
        uiView.pdfView.drawing(isEnable: drawingEnabled)

        // Обновляем видимость панели миниатюр.
        uiView.setThumbnailsVisible(showThumbnails)
    }
}
