import PencilKit

extension PKDrawing {
    
    /// Формирует DTO из видимых штрихов, учитывая маску после работы ластиком.
    func toDTO(pageIndex: Int, mediaBox: CGRect) -> DrawingAnnotationDTO {
        var strokesDTO: [StrokeDTO] = []
        
        _ = (try? PKDrawing(data: self.dataRepresentation())) ?? self
        
        for stroke in strokes {
            let brushSize = stroke.path.first.map { Double($0.size.width) } ?? 1.0
            let toolShortName = shortToolName(from: stroke.ink.inkType)
            let visibleRanges = normalizedRanges(for: stroke)
            
            for range in visibleRanges {
                guard let dto = makeStrokeDTO(
                    stroke: stroke,
                    range: range,
                    toolShortName: toolShortName,
                    brushSize: brushSize
                ) else {
                    continue
                }
                strokesDTO.append(dto)
            }
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
    
    /// Создаёт DTO из конкретного видимого диапазона штриха.
    func makeStrokeDTO(
        stroke: PKStroke,
        range: ClosedRange<CGFloat>,
        toolShortName: String,
        brushSize: Double
    ) -> StrokeDTO? {
        let points = interpolatedPoints(for: stroke, in: range)
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
    
    /// Возвращает валидные диапазоны пути, соответствующие видимой части штриха.
    func normalizedRanges(for stroke: PKStroke) -> [ClosedRange<CGFloat>] {
        let pointCount = stroke.path.count
        guard pointCount > 1 else { return [] }
        
        if !stroke.maskedPathRanges.isEmpty {
            return stroke.maskedPathRanges
        }
        
        let upperBound = CGFloat(pointCount - 1)
        return [0...upperBound]
    }
    
    /// Возвращает интерполированные точки в пределах диапазона B-сплайна.
    func interpolatedPoints(for stroke: PKStroke, in range: ClosedRange<CGFloat>) -> [PKStrokePoint] {
        guard let clampedRange = clamp(range, pathCount: stroke.path.count) else {
            return []
        }
        
        var collected: [PKStrokePoint] = []
        collected.append(stroke.path.interpolatedPoint(at: clampedRange.lowerBound))
        
        let slice = stroke.path.interpolatedPoints(
            in: clampedRange,
            by: .distance(1.0)
        )
        
        slice.forEach { point in
            appendUnique(point, to: &collected)
        }
        
        if clampedRange.upperBound > clampedRange.lowerBound {
            let endPoint = stroke.path.interpolatedPoint(at: clampedRange.upperBound)
            appendUnique(endPoint, to: &collected)
        }
        
        return collected
    }
    
    /// Обрезает диапазон по количеству контрольных точек.
    func clamp(_ range: ClosedRange<CGFloat>, pathCount: Int) -> ClosedRange<CGFloat>? {
        guard pathCount > 0 else { return nil }
        let maxValue = CGFloat(pathCount - 1)
        let lower = max(0, min(range.lowerBound, maxValue))
        let upper = max(lower, min(range.upperBound, maxValue))
        return lower...upper
    }
    
    /// Добавляет точку, избегая подряд идущих дубликатов.
    func appendUnique(_ point: PKStrokePoint, to array: inout [PKStrokePoint]) {
        guard let last = array.last else {
            array.append(point)
            return
        }
        
        if last.location.equalTo(point.location) {
            return
        }
        
        array.append(point)
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
