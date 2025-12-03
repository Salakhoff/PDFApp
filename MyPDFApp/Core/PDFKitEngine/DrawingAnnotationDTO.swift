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
//    let x: Double
//    let y: Double
    let width: Double
    let height: Double
}

struct StrokePointDTO: Codable {
    let x: Double
    let y: Double
    let size: Double
    let opacity: Double
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

extension DrawingAnnotationDTO {
    func toPKDrawing() -> PKDrawing {
        let strokes = self.strokes.compactMap { strokeDTO -> PKStroke? in
            let inkType = inkTypeFromShortName(strokeDTO.tool) ?? .pen
            let color = strokeDTO.color.toUIColor()
            let ink = PKInk(inkType, color: color)
            
            let pathPoints = strokeDTO.points.map { pointDTO in
                PKStrokePoint(
                    location: CGPoint(x: pointDTO.x, y: pointDTO.y),
                    timeOffset: 0.0,
                    size: CGSize(width: pointDTO.size, height: pointDTO.size),
                    opacity: CGFloat(pointDTO.opacity),
                    force: 0.0,
                    azimuth: CGFloat(1.57),
                    altitude: CGFloat(1.57)
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
    
    /// Преобразует короткое имя инструмента обратно в PKInk.InkType.
    private func inkTypeFromShortName(_ shortName: String) -> PKInk.InkType? {
        switch shortName.lowercased() {
        case "pen": return .pen
        case "marker": return .marker
        case "pencil": return .pencil
        case "monoline": return .monoline
        case "fountainpen": return .fountainPen
        case "watercolor": return .watercolor
        case "crayon": return .crayon
        default: return nil
        }
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
        // Сначала пробуем короткий формат
        switch rawValue.lowercased() {
        case "pen": self = .pen
        case "marker": self = .marker
        case "pencil": self = .pencil
        case "monoline": self = .monoline
        case "fountainpen": self = .fountainPen
        case "watercolor": self = .watercolor
        case "crayon": self = .crayon
        default:
            // Fallback на старый формат для обратной совместимости
            switch rawValue.lowercased() {
            case "com.apple.ink.pen": self = .pen
            case "com.apple.ink.marker": self = .marker
            case "com.apple.ink.pencil": self = .pencil
            case "com.apple.ink.monoline": self = .monoline
            case "com.apple.ink.fountainpen": self = .fountainPen
            case "com.apple.ink.watercolor": self = .watercolor
            case "com.apple.ink.crayon": self = .crayon
            default: return nil
            }
        }
    }
}
