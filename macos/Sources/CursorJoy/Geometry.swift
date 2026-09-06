import CoreGraphics

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension CGPoint {
    /// An empty rect would make an invalid range, so it passes the point through.
    func clamped(to rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return self }
        return CGPoint(x: x.clamped(to: rect.minX...rect.maxX),
                       y: y.clamped(to: rect.minY...rect.maxY))
    }
}

extension CGRect {
    /// Zero for a point inside the rect, so the nearest screen to a pointer
    /// sitting exactly on an edge is the one it is leaving.
    func squaredDistance(to point: CGPoint) -> CGFloat {
        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return dx * dx + dy * dy
    }
}
