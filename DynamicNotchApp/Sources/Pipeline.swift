// Pipeline — an action offered for files dropped on the notch (`NotchViewModel.availableActions`).

import Foundation

struct Pipeline: Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "bolt"
}
