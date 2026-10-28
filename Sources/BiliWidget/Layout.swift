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
