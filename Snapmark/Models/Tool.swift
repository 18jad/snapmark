import Foundation

/// The set of editing tools available in the toolbar.
enum Tool: String, CaseIterable, Identifiable {
    case select
    case grab
    case crop
    case blur
    case text
    case arrow
    case rectangle
    case ellipse
    case line

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .select:    return "Select"
        case .grab:      return "Grab"
        case .crop:      return "Crop"
        case .blur:      return "Blur"
        case .text:      return "Text"
        case .arrow:     return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse:   return "Ellipse"
        case .line:      return "Line"
        }
    }

    var sfSymbol: String {
        switch self {
        case .select:    return "cursorarrow"
        case .grab:      return "hand.raised.fill"
        case .crop:      return "crop"
        case .blur:      return "aqi.medium"
        case .text:      return "textformat"
        case .arrow:     return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .line:      return "line.diagonal"
        }
    }

    var shortcutHint: String {
        switch self {
        case .select:    return "V"
        case .grab:      return "H"
        case .crop:      return "C"
        case .blur:      return "B"
        case .text:      return "T"
        case .arrow:     return "A"
        case .rectangle: return "R"
        case .ellipse:   return "E"
        case .line:      return "L"
        }
    }
}
