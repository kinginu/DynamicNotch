import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// NSTextField that uses StableCell. Currently has no call sites.
class StableTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { StableCell.self }
        set { }
    }
}
