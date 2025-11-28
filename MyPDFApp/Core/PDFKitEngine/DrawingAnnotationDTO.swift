import PencilKit

struct DrawingAnnotationDTO: Codable {
    
    /// Индекс страницы
    let pageIndex: Int
    
    /// Размеры MediaBox страницы (для корректного позиционирования)
    let mediaBox: RectDTO
    
    /// Массив штрихов на странице
    let strokes: [StrokeDTO]
}

/// Прямоугольник (bounds страницы)
struct RectDTO: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct StrokePointDTO: Codable {
    let x: Double
    let y: Double
    let timeOffset: Double
    let width: Double
    let height: Double
    let opacity: Double
    let force: Double
    let azimuth: Double
    let altitude: Double
}

struct StrokeDTO: Codable {
    let tool: String
    let color: ColorDTO
    let points: [StrokePointDTO]
}

/// Цвет в формате RGBA
struct ColorDTO: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct SegmentDTO: Codable {
    
    /// Временное смещение от начала штриха (в секундах)
    let timeOffset: Double
    
    /// Основная точка
    let point: PointDTO
    
    /// Первая контрольная точка (для кривых Безье)
    let controlPoint1: PointDTO?
    
    /// Вторая контрольная точка (для кривых Безье)
    let controlPoint2: PointDTO?
}

/// Точка с координатами
struct PointDTO: Codable {
    let x: Double
    let y: Double
}

extension DrawingAnnotationDTO {
    func toPKDrawing() -> PKDrawing {
        let strokes = self.strokes.compactMap { strokeDTO -> PKStroke? in
            let inkType = PKInk.InkType(rawValue: strokeDTO.tool) ?? .pen
            let color = strokeDTO.color.toUIColor()
            let ink = PKInk(inkType, color: color)
            
            let pathPoints = strokeDTO.points.map { pointDTO in
                PKStrokePoint(
                    location: CGPoint(x: pointDTO.x, y: pointDTO.y),
                    timeOffset: pointDTO.timeOffset,
                    size: CGSize(width: pointDTO.width, height: pointDTO.height),
                    opacity: CGFloat(pointDTO.opacity),
                    force: CGFloat(pointDTO.force),
                    azimuth: CGFloat(pointDTO.azimuth),
                    altitude: CGFloat(pointDTO.altitude)
                )
            }
            
            guard !pathPoints.isEmpty else {
                print("⚠️ Пустой путь для штриха (инструмент: \(strokeDTO.tool))")
                return nil
            }
            
            let path = PKStrokePath(controlPoints: pathPoints, creationDate: Date())
            return PKStroke(ink: ink, path: path)
        }
        
        if strokes.isEmpty && !self.strokes.isEmpty {
            print("❌ Внимание: DTO содержит данные, но ни один штрих не был восстановлен!")
        }
        
        return PKDrawing(strokes: strokes)
    }
}

extension ColorDTO {
    func toUIColor() -> UIColor {
        return UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

extension PKInk.InkType {
    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "pen", "com.apple.ink.pen": self = .pen
        case "marker", "com.apple.ink.marker": self = .marker
        case "pencil", "com.apple.ink.pencil": self = .pencil
        case "monoline", "com.apple.ink.monoline": self = .monoline
        case "fountainpen", "com.apple.ink.fountainpen": self = .fountainPen
        case "watercolor", "com.apple.ink.watercolor": self = .watercolor
        case "crayon", "com.apple.ink.crayon": self = .crayon
        default: return nil
        }
    }
}
