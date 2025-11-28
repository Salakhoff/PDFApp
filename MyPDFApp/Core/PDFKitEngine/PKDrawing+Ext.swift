import PencilKit

extension PKDrawing {
    func toDTO(pageIndex: Int, mediaBox: CGRect) -> DrawingAnnotationDTO {
        let strokesDTO = self.strokes.map { stroke in
            let pointsDTO = stroke.path.map { point in
                StrokePointDTO(
                    x: Double(point.location.x),
                    y: Double(point.location.y),
                    timeOffset: point.timeOffset,
                    width: point.size.width,
                    height: point.size.height,
                    opacity: point.opacity,
                    force: point.force,
                    azimuth: point.azimuth,
                    altitude: point.altitude
                )
            }
            
            return StrokeDTO(
                tool: stroke.ink.inkType.rawValue,
                color: stroke.ink.color.toDTO(),
                points: pointsDTO
            )
        }
        
        return DrawingAnnotationDTO(
            pageIndex: pageIndex,
            mediaBox: RectDTO(
                x: Double(mediaBox.origin.x),
                y: Double(mediaBox.origin.y),
                width: Double(mediaBox.width),
                height: Double(mediaBox.height)
            ),
            strokes: strokesDTO
        )
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
