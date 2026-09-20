import SwiftUI
import UIKit

/// Shared foreground colours for the app and widgets. Keep text contrast in both appearances.
enum RhythmPalette {
    static let coral = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.61, blue: 0.49, alpha: 1)
            : UIColor(red: 0.68, green: 0.22, blue: 0.14, alpha: 1)
    })
    static let leaf = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.51, green: 0.79, blue: 0.65, alpha: 1)
            : UIColor(red: 0.18, green: 0.40, blue: 0.31, alpha: 1)
    })
    // Filled widget buttons use white text in both appearances.
    static let actionFill = Color(red: 0.18, green: 0.40, blue: 0.31)
}
