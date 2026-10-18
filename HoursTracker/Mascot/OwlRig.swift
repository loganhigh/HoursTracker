import SwiftUI

// MARK: - Owl rig
//
// Where the moving parts sit in each pose's art, so the owl can blink and
// wave a wing while the body stays put. Rects and pivots are fractions of
// the pose image (0…1). Eyes were found from the art's pupil shapes; wings
// are separate base/wing image layers cut along the shoulder
// (otto-<pose>-base / otto-<pose>-wing).

struct OwlRig {
    /// Each open eye's iris, as a fraction of the image.
    let eyes: [CGRect]
    /// Face colour the eyelids are drawn in.
    let lidHex: UInt32
    /// Shoulder point the wing layer rotates around; nil = no wing layer.
    let wingPivot: UnitPoint?

    static let none = OwlRig(eyes: [], lidHex: 0xF4D3B2, wingPivot: nil)

    static func forPose(_ pose: OwlPose) -> OwlRig {
        switch pose {
        case .calendar: return OwlRig(eyes: [CGRect(x: 0.2665, y: 0.2231, width: 0.1701, height: 0.144), CGRect(x: 0.5884, y: 0.2184, width: 0.173, height: 0.1481)], lidHex: 0xF5D6BA, wingPivot: nil)
        case .clipboard: return OwlRig(eyes: [CGRect(x: 0.2371, y: 0.2521, width: 0.1747, height: 0.149), CGRect(x: 0.5666, y: 0.2327, width: 0.1649, height: 0.1459)], lidHex: 0xF5D9BD, wingPivot: nil)
        case .coffee: return OwlRig(eyes: [CGRect(x: 0.2408, y: 0.2234, width: 0.1798, height: 0.1542), CGRect(x: 0.5788, y: 0.2221, width: 0.1749, height: 0.1534)], lidHex: 0xF6DBC0, wingPivot: nil)
        case .crown: return OwlRig(eyes: [CGRect(x: 0.2835, y: 0.2829, width: 0.1498, height: 0.1385), CGRect(x: 0.5711, y: 0.2881, width: 0.1492, height: 0.1412)], lidHex: 0xF9DBBE, wingPivot: nil)
        case .idle: return OwlRig(eyes: [CGRect(x: 0.2676, y: 0.2245, width: 0.1646, height: 0.149), CGRect(x: 0.5725, y: 0.2248, width: 0.1679, height: 0.1513)], lidHex: 0xF4D2B2, wingPivot: nil)
        case .oops: return OwlRig(eyes: [CGRect(x: 0.3126, y: 0.2581, width: 0.1563, height: 0.1541), CGRect(x: 0.5848, y: 0.2166, width: 0.1554, height: 0.1502)], lidHex: 0xFADFC5, wingPivot: nil)
        case .peek: return OwlRig(eyes: [CGRect(x: 0.2648, y: 0.399, width: 0.155, height: 0.2612), CGRect(x: 0.542, y: 0.3605, width: 0.1559, height: 0.2581)], lidHex: 0xFADFC5, wingPivot: nil)
        case .pin: return OwlRig(eyes: [CGRect(x: 0.3755, y: 0.2232, width: 0.1138, height: 0.1467), CGRect(x: 0.5931, y: 0.2366, width: 0.1141, height: 0.1408)], lidHex: 0xF6D6B6, wingPivot: nil)
        case .shield: return OwlRig(eyes: [CGRect(x: 0.2629, y: 0.2185, width: 0.1646, height: 0.1541), CGRect(x: 0.5771, y: 0.2248, width: 0.169, height: 0.1519)], lidHex: 0xF5D6BA, wingPivot: nil)
        case .wave: return OwlRig(eyes: [CGRect(x: 0.2383, y: 0.2604, width: 0.1399, height: 0.1432), CGRect(x: 0.5013, y: 0.225, width: 0.1414, height: 0.1442)], lidHex: 0xF4D3B2, wingPivot: UnitPoint(x: 0.7224, y: 0.5922))
        case .wrench: return OwlRig(eyes: [CGRect(x: 0.3672, y: 0.2264, width: 0.1399, height: 0.143), CGRect(x: 0.6315, y: 0.2313, width: 0.1359, height: 0.149)], lidHex: 0xF3D4B6, wingPivot: nil)
        case .bell: return OwlRig(eyes: [], lidHex: 0xF4D4B7, wingPivot: UnitPoint(x: 0.6771, y: 0.603))
        case .point: return OwlRig(eyes: [], lidHex: 0xF9DCC1, wingPivot: UnitPoint(x: 0.6883, y: 0.565))
        default: return .none
        }
    }
}
