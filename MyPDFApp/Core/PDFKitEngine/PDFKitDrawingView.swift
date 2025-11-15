import UIKit
import PencilKit
import PDFKit

/// UIView-обёртка над PKCanvasView для рисования поверх PDF-страниц.
/// Связывает PencilKit с PDFKit, синхронизируя рисунки с PDFDocumentPage.
final class PDFKitDrawingView: UIView, PKCanvasViewDelegate {

    // MARK: - Mode Type

    /// Режим работы canvas: рисование активно или только просмотр.
    enum ModeType {
        /// Режим рисования - canvas принимает пользовательский ввод.
        case drawing
        /// Режим по умолчанию - canvas не реагирует на прикосновения.
        case `default`
    }

    // MARK: - Properties

    /// Ссылка на родительский PDFView (опционально, для дополнительных операций).
    var pdf: PDFView?

    /// Страница PDF, связанная с этим canvas.
    var page: PDFDocumentPage?

    /// Коллбек, вызываемый при каждом изменении рисунка для синхронизации с PDFDocumentPage.
    var onDrawingChanged: ((PKDrawing) -> Void)?

    // MARK: - Subviews

    /// Основной canvas PencilKit для рисования.
    let canvasView: PKCanvasView = {
        let view = PKCanvasView(frame: .zero)
        view.drawingPolicy = .anyInput // Разрешаем рисование любым инструментом (палец, Apple Pencil).
        view.backgroundColor = .clear // Прозрачный фон, чтобы видеть PDF под ним.
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false // По умолчанию отключено, включается через enable(mode:).
        return view
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        canvasView.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// Переключает режим работы canvas между рисованием и просмотром.
    /// - Parameter mode: Режим работы (.drawing включает взаимодействие, .default отключает).
    func enable(mode: ModeType) {
        switch mode {
        case .drawing:
            canvasView.isUserInteractionEnabled = true
        case .default:
            canvasView.isUserInteractionEnabled = false
        }
    }

    // MARK: - PKCanvasViewDelegate

    /// Обрабатывает изменения в рисунке и уведомляет о них через коллбек.
    /// Вызывается автоматически при каждом штрихе, удалении или изменении рисунка.
    /// - Parameter canvasView: Canvas, в котором произошли изменения.
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        onDrawingChanged?(canvasView.drawing)
    }
}

// MARK: - Private Setup

private extension PDFKitDrawingView {

    /// Настраивает layout constraints для canvas, чтобы он заполнял всю область view.
    func setupViews() {
        addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: topAnchor),
            canvasView.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: leadingAnchor)
        ])
    }
}
