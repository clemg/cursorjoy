import AppKit

/// Whatever pointer the system is showing right now — arrow, pointing hand,
/// I-beam, a resize arrow, an app's own artwork — together with the two things
/// the swing needs: where it pivots, and where its weight is.
struct CursorShape {
    let image: NSImage
    /// The pointer's tip, measured from the image's top-left corner, in points.
    let hotSpot: CGPoint
    /// Unit vector from the hot spot to the artwork's centre of mass, y up.
    /// A pointing hand hangs differently from an arrow, and this is why.
    let centreOfMass: CGVector
    /// Furthest the drawn pixels get from the hot spot, in points. Rotation is
    /// about the hot spot, so this bounds the shape at any angle.
    let reach: CGFloat

    static let arrow = CursorShape(NSCursor.arrow)

    /// The measured system arrow, used when a shape's pixels cannot be scanned.
    static let defaultMass = CGVector(dx: 0.3989, dy: -0.9170)

    init(_ cursor: NSCursor) {
        image = cursor.image
        hotSpot = cursor.hotSpot
        let scan = Self.scan(image, hotSpot: cursor.hotSpot)
        centreOfMass = scan.centreOfMass
        reach = scan.reach
    }

    /// One pass over the artwork's alpha: where its weight is, and how far its
    /// visible pixels get from the hot spot. Transparent padding is ignored, so
    /// the numbers describe the pointer you can actually see.
    private static func scan(_ image: NSImage,
                             hotSpot: CGPoint) -> (centreOfMass: CGVector, reach: CGFloat) {
        let fallback = (defaultMass, max(image.size.width, image.size.height))

        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              cg.bitsPerPixel == 32, cg.bitsPerComponent == 8
        else { return fallback }

        let info = cg.alphaInfo
        guard info == .premultipliedFirst || info == .first
                || info == .premultipliedLast || info == .last
        else { return fallback }
        let alphaOffset = (info == .premultipliedFirst || info == .first) ? 0 : 3

        var weight = 0.0, sumX = 0.0, sumY = 0.0
        var minX = cg.width, maxX = -1, minY = cg.height, maxY = -1
        for y in 0..<cg.height {
            let row = bytes + y * cg.bytesPerRow
            for x in 0..<cg.width {
                let alpha = Double(row[x * 4 + alphaOffset])
                guard alpha > 0 else { continue }
                weight += alpha
                sumX += Double(x) * alpha
                sumY += Double(y) * alpha
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard weight > 0, maxX >= 0 else { return fallback }

        let scaleX = image.size.width / CGFloat(cg.width)
        let scaleY = image.size.height / CGFloat(cg.height)
        let dx = CGFloat(sumX / weight) * scaleX - hotSpot.x
        let dy = hotSpot.y - CGFloat(sumY / weight) * scaleY
        let length = hypot(dx, dy)
        let mass = length > 0.001 ? CGVector(dx: dx / length, dy: dy / length) : fallback.0

        let corners = [(minX, minY), (minX, maxY + 1), (maxX + 1, minY), (maxX + 1, maxY + 1)]
        let reach = corners.map { corner in
            hypot(CGFloat(corner.0) * scaleX - hotSpot.x, CGFloat(corner.1) * scaleY - hotSpot.y)
        }.max() ?? fallback.1

        return (mass, reach)
    }
}

/// Reads the pointer the whole system is displaying.
///
/// `NSCursor.currentSystem` hands back a fresh `NSImage` on every call, so
/// identity tells us nothing: shapes are recognised by hashing their pixels, and
/// an unchanged hash means the layer keeps the texture it already has.
final class CursorShapeReader {
    private(set) var shape = CursorShape.arrow
    private var cache: [Int: CursorShape] = [:]
    private var currentKey: Int?
    private var missesInARow = 0

    /// False when the system is showing something we cannot read: the caller
    /// should step aside and let the real pointer show rather than draw the
    /// wrong shape.
    private(set) var isReadable = true

    func refresh() {
        autoreleasepool {
            guard let cursor = NSCursor.currentSystem else {
                missesInARow += 1
                // A stray nil between two good reads should not make it blink.
                if missesInARow > 4 { isReadable = false }
                return
            }
            missesInARow = 0
            isReadable = true

            guard let key = fingerprint(of: cursor), key != currentKey else { return }
            currentKey = key
            if let known = cache[key] {
                shape = known
                return
            }
            let measured = CursorShape(cursor)
            // The system's cursors are a short list; more than this is a runaway.
            // ponytail: stops caching at 64 shapes instead of evicting; make it
            // an LRU if a real session ever cycles through more than that.
            if cache.count < 64 { cache[key] = measured }
            shape = measured
        }
    }

    private func fingerprint(of cursor: NSCursor) -> Int? {
        guard let cg = cursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return nil }
        var hasher = Hasher()
        hasher.combine(cursor.hotSpot.x)
        hasher.combine(cursor.hotSpot.y)
        hasher.combine(cg.width)
        hasher.combine(cg.height)
        hasher.combine(bytes: UnsafeRawBufferPointer(start: bytes, count: CFDataGetLength(data)))
        return hasher.finalize()
    }

    func reset() {
        shape = .arrow
        currentKey = nil
        isReadable = true
        missesInARow = 0
    }
}

/// Draws a cursor shape with Core Animation: cheap to move and turn every frame.
/// `place(hotSpot:)` is the point the real pointer is at; the shape rotates about it.
final class PointerLayer: CALayer {
    private var current: NSImage?

    override init() {
        super.init()
        // Ghosts and small pointer sizes shrink the artwork; the default filter
        // aliases when they do.
        minificationFilter = .trilinear
    }

    required init?(coder: NSCoder) { fatalError() }
    override init(layer: Any) { super.init(layer: layer) }

    func place(shape: CursorShape, hotSpot: CGPoint, angleDeg: Double,
               scale: CGFloat, opacity: Float = 1) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if current !== shape.image {
            current = shape.image
            contents = shape.image
            bounds = CGRect(origin: .zero, size: shape.image.size)
            // NSCursor measures the hot spot from the top-left; layers are y-up.
            anchorPoint = CGPoint(x: shape.hotSpot.x / max(shape.image.size.width, 1),
                                  y: 1 - shape.hotSpot.y / max(shape.image.size.height, 1))
        }
        position = hotSpot
        self.opacity = opacity
        setAffineTransform(CGAffineTransform(rotationAngle: -CGFloat(angleDeg) * .pi / 180)
            .scaledBy(x: scale, y: scale))
        CATransaction.commit()
    }
}
