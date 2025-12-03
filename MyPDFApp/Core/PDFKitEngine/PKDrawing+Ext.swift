import PencilKit

extension PKDrawing {
    func toDTO(pageIndex: Int, mediaBox: CGRect) -> DrawingAnnotationDTO {
        let strokesDTO = self.strokes.map { stroke in
            let pointsDTO = stroke.path.map { point in
                StrokePointDTO(
                    x: Double(point.location.x),
                    y: Double(point.location.y),
                    opacity: point.opacity
                )
            }
            
            let toolShortName = shortToolName(from: stroke.ink.inkType)
            let strokeBounds = stroke.renderBounds
            
            // Берем размер из первой точки (все точки имеют одинаковый размер)
            let brushSize = stroke.path.first.map { Double($0.size.width) } ?? 1.0
            
            return StrokeDTO(
                tool: toolShortName,
                color: stroke.ink.color.toDTO(),
                size: brushSize,
                points: pointsDTO,
                bounds: RectDTO(
                    x: Double(strokeBounds.origin.x),
                    y: Double(strokeBounds.origin.y),
                    width: Double(strokeBounds.width),
                    height: Double(strokeBounds.height)
                )
            )
        }
        
        return DrawingAnnotationDTO(
            pageIndex: pageIndex,
            mediaBox: RectMediaBoxDTO(
                width: Double(mediaBox.width),
                height: Double(mediaBox.height)
            ),
            strokes: strokesDTO
        )
    }
    
    /// Преобразует PKInk.InkType в короткое читаемое имя для JSON.
    private func shortToolName(from inkType: PKInk.InkType) -> String {
        switch inkType {
        case .pen: "pen"
        case .marker: "marker"
        case .pencil: "pencil"
        case .monoline: "monoline"
        case .fountainPen: "fountainpen"
        case .watercolor: "watercolor"
        case .crayon: "crayon"
        case .reed: "reed"
        default: "pen"
        }
    }
}

// MARK: - Вспомогательные расширения

extension UIColor {
    /// Конвертирует UIColor в ColorDTO
    func toDTO() -> ColorDTO {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        return ColorDTO(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }
}
