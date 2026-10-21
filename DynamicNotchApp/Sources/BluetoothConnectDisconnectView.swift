import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

struct BluetoothConnectDisconnectView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1.0) {
            Text("")
                .lineLimit(nil as Int?)
                .truncationMode(.tail)

            HStack {
                Image(systemName: "questionmark")
                    .font(nil as Font?)
                    .foregroundStyle(Color.nonShockingWhite)
            }
        }
        .padding(.horizontal, 0)

        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
