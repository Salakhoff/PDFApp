import PencilKit

extension PKDrawing {
    
    /// Формирует DTO из видимых штрихов.
    /// Учитывает ластик: PKDrawing.strokes содержит информацию о всех операциях.
    /// При экспорте берём текущее состояние рисунка - ластик уже применён.
    func toDTO(pageIndex: Int, mediaBox: CGRect) -> DrawingAnnotationDTO {
        var strokesDTO: [StrokeDTO] = []
        
        for stroke in strokes {
            let brushSize = stroke.path.first.map { Double($0.size.width) } ?? 1.0
            let toolShortName = shortToolName(from: stroke.ink.inkType)
            
            guard let dto = makeStrokeDTO(
                stroke: stroke,
                toolShortName: toolShortName,
                brushSize: brushSize
            ) else {
                continue
            }
            strokesDTO.append(dto)
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
        @unknown default: "pen"
        }
    }
}

// MARK: - Private Helpers

private extension PKDrawing {
    
    /// Создаёт DTO из всех точек штриха.
    func makeStrokeDTO(
        stroke: PKStroke,
        toolShortName: String,
        brushSize: Double
    ) -> StrokeDTO? {
        let points = Array(stroke.path)
        guard points.count >= 2 else { return nil }
        
        let pointsDTO = points.map { point in
            StrokePointDTO(
                x: Double(point.location.x),
                y: Double(point.location.y),
                opacity: point.opacity
            )
        }
        
        let boundsRect = calculateBounds(for: points, brushSize: brushSize)
        
        return StrokeDTO(
            tool: toolShortName,
            color: stroke.ink.color.toDTO(),
            size: brushSize,
            points: pointsDTO,
            bounds: boundsRect
        )
    }
    
    /// Рассчитывает bounds для набора точек с учётом толщины кисти.
    func calculateBounds(for points: [PKStrokePoint], brushSize: Double) -> RectDTO {
        guard !points.isEmpty else {
            return RectDTO(x: 0, y: 0, width: 0, height: 0)
        }
        
        let xs = points.map { Double($0.location.x) }
        let ys = points.map { Double($0.location.y) }
        
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? minX
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? minY
        let padding = brushSize / 2
        
        return RectDTO(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + brushSize,
            height: (maxY - minY) + brushSize
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
