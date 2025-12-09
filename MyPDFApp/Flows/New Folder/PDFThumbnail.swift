import SwiftUI
import PDFKit

/// Кастомный компонент для отображения миниатюр страниц PDF-документа.
/// Позволяет быстро навигироваться по страницам документа.
struct PDFThumbnailView: View {
    
    // MARK: - Properties
    
    /// PDF-документ для генерации миниатюр.
    let pdfDocument: PDFDocument?
    
    /// Индекс текущей отображаемой страницы.
    let currentPageIndex: Int
    
    /// Коллбек при выборе страницы (передаётся индекс страницы).
    let onPageSelected: (Int) -> Void
    
    /// Ширина миниатюры (будет вычисляться на основе ширины экрана).
    @State private var thumbnailWidth: CGFloat = 100
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let pdfDocument = pdfDocument {
                        ForEach(0..<pdfDocument.pageCount, id: \.self) { index in
                            thumbnailItem(
                                for: pdfDocument.page(at: index),
                                index: index,
                                width: geometry.size.width - 32 // Отступы по 16 с каждой стороны
                            )
                        }
                    } else {
                        // Показываем placeholder, если документ не загружен
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .padding(.vertical, 16)
            }
            .onAppear {
                // Вычисляем ширину миниатюры при появлении
                thumbnailWidth = geometry.size.width - 32
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                // Обновляем ширину при изменении размера экрана
                thumbnailWidth = newWidth - 32
            }
        }
    }
    
    // MARK: - Private Views
    
    /// Создаёт элемент миниатюры для конкретной страницы.
    /// - Parameters:
    ///   - page: PDF-страница для отображения.
    ///   - index: Индекс страницы в документе.
    ///   - width: Ширина миниатюры.
    /// - Returns: View с миниатюрой страницы.
    @ViewBuilder
    private func thumbnailItem(for page: PDFPage?, index: Int, width: CGFloat) -> some View {
        if let page = page {
            let isSelected = index == currentPageIndex
            
            Button {
                onPageSelected(index)
            } label: {
                VStack(spacing: 4) {
                    // Миниатюра страницы
                    Image(uiImage: generateThumbnail(for: page, width: width))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: width)
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isSelected ? Color.black : Color.clear,
                                    lineWidth: isSelected ? 3 : 0
                                )
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    // Номер страницы
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundColor(isSelected ? .black : .gray)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Private Methods
    
    /// Генерирует миниатюру для указанной страницы PDF.
    /// - Parameters:
    ///   - page: PDF-страница для генерации миниатюры.
    ///   - width: Желаемая ширина миниатюры.
    /// - Returns: UIImage с миниатюрой страницы.
    private func generateThumbnail(for page: PDFPage, width: CGFloat) -> UIImage {
        // Получаем размеры страницы
        let pageRect = page.bounds(for: .mediaBox)
        let aspectRatio = pageRect.height / pageRect.width
        
        // Вычисляем размер миниатюры с сохранением пропорций
        let thumbnailSize = CGSize(
            width: width,
            height: width * aspectRatio
        )
        
        // Генерируем миниатюру используя PDFKit
        let thumbnail = page.thumbnail(of: thumbnailSize, for: .mediaBox)
        
        return thumbnail
    }
}
