import SwiftUI
import PencilKit

/// Менеджер состояния инструментов рисования.
/// Хранит текущий выбранный инструмент и обеспечивает его применение к canvas.
@Observable
final class ToolStateManager {
    /// Текущий выбранный инструмент рисования.
    var currentTool = CustomDrawingTool()
    
    /// Применяет текущий инструмент к указанному PKCanvasView.
    /// - Parameter canvasView: Canvas, к которому нужно применить инструмент.
    func applyTool(to canvasView: PKCanvasView) {
        canvasView.tool = currentTool.pkTool
    }
}
