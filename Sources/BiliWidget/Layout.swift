import Foundation

enum WidgetLayout {
    static let minimum = CGSize(width:282,height:310)
    static let maximum = CGSize(width:850,height:1050)
    static func scale(_ size: CGSize, compact: Bool) -> CGFloat {
        max(0.78,min(2.1,min(size.width/354,size.height/(compact ? 350 : 430))))
    }
    static func bounded(_ size: CGSize) -> CGSize {
        CGSize(width:max(minimum.width,min(maximum.width,size.width)),height:max(minimum.height,min(maximum.height,size.height)))
    }
}

/// Rendering bounds are safe even while a numeric text field contains an invalid
/// draft. The store still validates the original values before saving.
enum ProgressInput {
    static func fraction(_ value: Double) -> Double {
        value.isFinite ? max(0, min(1, value)) : 0
    }
    static func sliderUpperBound(_ duration: Double) -> Double {
        duration.isFinite ? max(1, min(86400, duration)) : 1
    }
    static func sliderSeconds(_ seconds: Double, duration: Double) -> Double {
        seconds.isFinite ? max(0, min(sliderUpperBound(duration), seconds)) : 0
    }
}

/// Restores native window frames on valid displays, including negative origins.
enum WindowPlacement {
    static func clamp(_ proposed: CGRect, screens: [CGRect]) -> CGRect {
        let available=screens.filter { !$0.isEmpty && !$0.isNull && !$0.isInfinite }
        guard let first=available.first else { return proposed }
        let valid=[proposed.minX,proposed.minY,proposed.width,proposed.height].allSatisfy(\.isFinite) && proposed.width > 0 && proposed.height > 0
        let frame=valid ? proposed : CGRect(x:first.midX-177,y:first.midY-215,width:354,height:430)
        func area(_ screen:CGRect) -> CGFloat {
            let intersection=screen.intersection(frame)
            return intersection.isNull ? 0 : intersection.width*intersection.height
        }
        func distance(_ screen:CGRect) -> CGFloat {
            let x=max(screen.minX,min(frame.midX,screen.maxX)),y=max(screen.minY,min(frame.midY,screen.maxY))
            return hypot(frame.midX-x,frame.midY-y)
        }
        let screen=available.sorted { a,b in area(a) == area(b) ? distance(a) < distance(b) : area(a) > area(b) }.first!
        let width=min(frame.width,screen.width),height=min(frame.height,screen.height)
        return CGRect(x:max(screen.minX,min(frame.minX,screen.maxX-width)),y:max(screen.minY,min(frame.minY,screen.maxY-height)),width:width,height:height)
    }
}
