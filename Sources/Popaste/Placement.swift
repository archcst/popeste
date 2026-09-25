import Foundation
import CoreGraphics

/// AppKit screen coordinates (origin at the bottom left of the primary display).
enum PickerPlacement {
    /// Expand from the collapsed search bar: down first, then up if it fits better.
    static func resizedFrame(_ current: CGRect, visibleScreen: CGRect, desiredSize: CGSize) -> CGRect {
        let bounds = visibleScreen.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(desiredSize.width, bounds.width), height: min(desiredSize.height, bounds.height))
        let below = current.maxY - bounds.minY
        let above = bounds.maxY - current.minY
        let upward = below < size.height && (above >= size.height || above > below)
        return CGRect(x: min(max(current.minX, bounds.minX), bounds.maxX - size.width),
                      y: min(max(upward ? current.minY : current.maxY - size.height, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func frame(caret: CGRect?, mouse: CGPoint, visibleScreen: CGRect, desiredSize: CGSize = CGSize(width: 440, height: 420)) -> CGRect {
        let bounds = visibleScreen.insetBy(dx: 8, dy: 8)
        let point = caret.map { CGPoint(x: $0.minX, y: $0.minY) } ?? mouse
        let width = min(desiredSize.width, bounds.width)
        var height = min(desiredSize.height, bounds.height)
        let below = point.y - 8 - bounds.minY
        let aboveOrigin = (caret?.maxY ?? point.y) + 8
        let above = bounds.maxY - aboveOrigin
        let useBelow = above < height && (below >= height || below > above)
        let available = useBelow ? below : above
        // Preserve search and actions while reducing the scrolling viewport if needed.
        if available >= 200 { height = min(height, available) }
        let y = useBelow ? point.y - height - 8 : aboveOrigin
        return CGRect(x: min(max(point.x, bounds.minX), bounds.maxX - width),
                      y: min(max(y, bounds.minY), bounds.maxY - height),
                      width: width, height: height)
    }
}
