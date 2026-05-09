import Foundation

/// User's chosen weight unit for the workout tracker. Defaults to pounds.
/// Persisted via @AppStorage("workout_unit") wherever needed.
enum WorkoutUnit: String, CaseIterable, Identifiable {
    case pounds = "lb"
    case kilograms = "kg"

    var id: String { rawValue }
    var label: String { rawValue }

    /// Single-tick increment for fine adjustments (small ↑/↓ button).
    var smallStep: Double {
        switch self {
        case .pounds: return 5      // 5 lb = one pair of small plates
        case .kilograms: return 2.5 // 2.5 kg = standard small plate pair
        }
    }
    /// Double-tick increment for progressive overload (big ↑↑ button).
    var largeStep: Double {
        switch self {
        case .pounds: return 10
        case .kilograms: return 5
        }
    }

    /// Convert a canonical lb-denominated default to the user's unit,
    /// snapped to the small-step grid so the number stays plate-friendly.
    func displayValue(fromPounds lb: Double) -> Double {
        switch self {
        case .pounds:
            return lb
        case .kilograms:
            let kg = lb * 0.453592
            return (kg / smallStep).rounded() * smallStep
        }
    }

    /// Pretty-formats a numeric step for display ("5", "2.5").
    func formatStep(_ s: Double) -> String {
        s.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(s))"
            : String(format: "%g", s)
    }
}
