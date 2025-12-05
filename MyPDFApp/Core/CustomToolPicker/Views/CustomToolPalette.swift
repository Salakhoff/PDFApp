import SwiftUI

struct CustomToolPalette: View {
    @Bindable var tool: CustomDrawingTool
    @State private var showColorPicker = false
    @Binding var isUsingPencil: Bool
    
    /// Коллбек для уведомления об изменении инструмента (опционально).
    var onToolChanged: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ToolType.allCases, id: \.self) { toolType in
                        ToolButton(
                            toolType: toolType,
                            isSelected: tool.type == toolType,
                            action: {
                                tool.type = toolType
                                onToolChanged?()
                            }
                        )
                    }
                    
                    Button(action: { showColorPicker.toggle() }) {
                        Circle()
                            .fill(tool.color)
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 8)
        .sheet(isPresented: $showColorPicker) {
            ColorPickerSheet(selectedColor: $tool.color)
        }
        .onChange(of: tool.type) { _, _ in
            onToolChanged?()
        }
        .onChange(of: tool.color) { _, _ in
            onToolChanged?()
        }
        .onChange(of: tool.width) { _, _ in
            onToolChanged?()
        }
    }
}
