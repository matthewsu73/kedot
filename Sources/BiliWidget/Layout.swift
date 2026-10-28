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
