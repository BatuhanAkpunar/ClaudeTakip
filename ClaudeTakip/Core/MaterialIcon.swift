import SwiftUI

enum BI: String {
    case arrowClockwise = "arrow.clockwise"
    case boxArrowRight = "rectangle.portrait.and.arrow.right"

    func view(size: CGFloat = 16) -> some View {
        Image(systemName: rawValue)
            .font(.system(size: size))
    }
}
