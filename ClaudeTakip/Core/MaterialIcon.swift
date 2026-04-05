import SwiftUI

enum BI: String {
    case globe2 = "globe"
    case arrowClockwise = "arrow.clockwise"
    case boxArrowRight = "rectangle.portrait.and.arrow.right"
    case power = "power"

    func view(size: CGFloat = 16) -> some View {
        Image(systemName: rawValue)
            .font(.system(size: size))
    }
}
