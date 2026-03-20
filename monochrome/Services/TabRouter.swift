import Foundation
import Combine
import SwiftUI

class TabRouter: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var pendingLibraryFilter: LibraryFilter? = nil
}
