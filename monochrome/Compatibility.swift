import SwiftUI

// MARK: - Navigation Compatibility (iOS 15 fallbacks)

struct LegacyNavigationDestination: Hashable {
    let value: AnyHashable

    var base: Any {
        value.base
    }

    init<T: Hashable>(_ value: T) {
        self.value = AnyHashable(value)
    }
}


enum CompatScrollDismissMode {
    case interactively
    case immediately
    case never
}

struct CompatNavigationPath {
    fileprivate var storage: Any
    fileprivate var legacySelection: LegacyNavigationDestination?

    init() {
        if #available(iOS 16.0, *) {
            storage = SwiftUI.NavigationPath()
        } else {
            storage = ()
        }
        legacySelection = nil
    }

    @available(iOS 16.0, *)
    fileprivate var swiftPath: SwiftUI.NavigationPath {
        get { storage as? SwiftUI.NavigationPath ?? SwiftUI.NavigationPath() }
        set { storage = newValue }
    }

    mutating func append<T: Hashable>(_ value: T) {
        if #available(iOS 16.0, *) {
            swiftPath.append(value)
        } else {
            legacySelection = LegacyNavigationDestination(value)
        }
    }

    mutating func removeLast() {
        if #available(iOS 16.0, *) {
            swiftPath.removeLast()
        } else {
            legacySelection = nil
        }
    }
}

struct CompatNavigationStack<Content: View>: View {
    @Binding var path: CompatNavigationPath
    let legacyDestination: (LegacyNavigationDestination) -> AnyView
    let content: Content

    init(path: Binding<CompatNavigationPath>,
         legacyDestination: @escaping (LegacyNavigationDestination) -> AnyView,
         @ViewBuilder content: () -> Content) {
        self._path = path
        self.legacyDestination = legacyDestination
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: swiftPathBinding) {
                content
            }
        } else {
            NavigationView {
                ZStack {
                    content
                    LegacyNavigationLink(selection: legacySelectionBinding, destination: legacyDestination)
                }
            }
        }
    }

    @available(iOS 16.0, *)
    private var swiftPathBinding: Binding<SwiftUI.NavigationPath> {
        Binding(
            get: { path.swiftPath },
            set: { path.swiftPath = $0 }
        )
    }

    private var legacySelectionBinding: Binding<LegacyNavigationDestination?> {
        Binding(
            get: { path.legacySelection },
            set: { path.legacySelection = $0 }
        )
    }
}

struct CompatNavigationView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
        }
    }
}

private struct LegacyNavigationLink: View {
    @Binding var selection: LegacyNavigationDestination?
    let destination: (LegacyNavigationDestination) -> AnyView

    var body: some View {
        NavigationLink(
            destination: legacyDestinationView,
            isActive: legacyIsActiveBinding
        ) {
            EmptyView()
        }
        .hidden()
    }

    private var legacyDestinationView: AnyView {
        guard let selection else { return AnyView(EmptyView()) }
        return destination(selection)
    }

    private var legacyIsActiveBinding: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { isActive in
                if !isActive { selection = nil }
            }
        )
    }
}

// MARK: - View Modifier Compatibility (iOS 15 fallbacks)

extension View {
    @ViewBuilder
    func compatScrollContentBackground(_ visibility: Bool) -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(visibility ? .visible : .hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatPresentationDetents(medium: Bool = false, large: Bool = false) -> some View {
        if #available(iOS 16.0, *) {
            let detents: Set<PresentationDetent> = {
                var d = Set<PresentationDetent>()
                if medium { d.insert(.medium) }
                if large { d.insert(.large) }
                return d
            }()
            self.presentationDetents(detents)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatPresentationDragIndicator() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatPresentationBackground(_ color: Color) -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(color)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatSafeAreaPadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        if #available(iOS 17.0, *) {
            self.safeAreaPadding(edges, length)
        } else if let length {
            self.padding(edges, length)
        } else {
            self.padding(edges)
        }
    }

    @ViewBuilder
    func compatToolbarBackground(_ visibility: Visibility) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            self.toolbarBackground(visibility, for: .navigationBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func compatToolbarBackground<S: ShapeStyle>(_ style: S) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            self.toolbarBackground(style, for: .navigationBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func compatToolbarColorScheme(_ scheme: ColorScheme?) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            self.toolbarColorScheme(scheme, for: .navigationBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func compatNavigationDestination<D: Hashable, C: View>(for data: D.Type,
                                                           @ViewBuilder destination: @escaping (D) -> C) -> some View {
        if #available(iOS 16.0, *) {
            self.navigationDestination(for: data, destination: destination)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatItalic() -> some View {
        if #available(iOS 16.0, *) {
            self.italic()
        } else {
            self
        }
    }

    @ViewBuilder
    func compatScrollDismissesKeyboard(_ mode: CompatScrollDismissMode) -> some View {
        if #available(iOS 16.0, *) {
            switch mode {
            case .interactively:
                self.scrollDismissesKeyboard(.interactively)
            case .immediately:
                self.scrollDismissesKeyboard(.immediately)
            case .never:
                self.scrollDismissesKeyboard(.never)
            }
        } else {
            self
        }
    }
}
