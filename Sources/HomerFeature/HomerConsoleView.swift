import ComposableArchitecture
import HomerAgents
import HomerContinuations
import HomerCore
import HomerCosts
import HomerProcessDetail
import HomerSignIn
import HomerUI
import SwiftUI

/// The Homer console. `leading` heads it, before the page picker — the host's section switcher
/// in Bridge Commander, the console's title in the standalone app; the instance menu at the
/// other end switches between the instances (⌘1…⌘9 too), each of which stays signed in.
///
/// The host sends the store `start` once at launch (open questions are polled from then on, so
/// a badge can show them before the console is ever on screen) and sets the text size with
/// `homerUIFontScale(_:)`.
public struct HomerConsoleView<Leading: View>: View {
	@Bindable
	private var store: StoreOf<HomerConsoleReducer>
	private let leading: Leading

	public init(store: StoreOf<HomerConsoleReducer>, @ViewBuilder leading: () -> Leading) {
		self.store = store
		self.leading = leading()
	}

	public var body: some View {
		VStack(spacing: 0) {
			headerView
			Divider()
			content
		}
		.onAppear { store.send(.appeared) }
		.onDisappear { store.send(.disappeared) }
	}

	private var selectedInstanceStore: StoreOf<HomerInstanceReducer>? {
		let id = store.selectedInstanceID
		return store.scope(\.instances[id: id], action: \.instances[id: id])
	}

	/// The selected instance's lists, as opposed to a sign-in form or a progress spinner.
	private var showsConsole: Bool {
		store.addInstance == nil && store.selectedInstance?.user != nil
	}

	@ViewBuilder
	private var content: some View {
		if let addInstanceStore = store.scope(\.addInstance, action: \.addInstance) {
			HomerLoginView(store: addInstanceStore)
		}
		else if let instanceStore = selectedInstanceStore {
			HomerInstanceView(store: instanceStore, tab: store.tab)
				// A fresh view per instance: the table's selection and the form's focus are its own.
				.id(store.selectedInstanceID)
		}
	}

	// MARK: - Header

	private var headerView: some View {
		HStack {
			HStack(spacing: 12) {
				leading

				if showsConsole {
					Picker("Homer page", selection: $store.tab) {
						ForEach(availableTabs, id: \.self) { tab in
							Text(title(of: tab)).tag(tab)
						}
					}
					.pickerStyle(.segmented)
					.labelsHidden()
					.fixedSize()
					.overlay { openQuestionsDot }
				}
			}

			Spacer()

			HStack(spacing: 12) {
				if !store.instances.isEmpty {
					instanceMenu
				}

				if showsConsole, let instance = store.selectedInstance, let user = instance.user {
					HeaderButton(
						icon: "arrow.clockwise",
						tooltip: "Refresh (⌘R)",
						color: .blue,
						action: { store.send(.refreshTapped) }
					)
					// A host with a ⌘R of its own disables it while the console is shown (Bridge
					// Commander's `RootRepositoryView` does), so this one has the key to itself.
					.keyboardShortcut("r", modifiers: .command)

					HeaderButton(
						icon: "safari",
						tooltip: "Open this page of the web console",
						action: openCurrentPageInWebConsole
					)

					accountMenu(user: user, instance: instance)
				}
			}
		}
		// The height its 30 pt buttons give it, signed out too (there are none then), so the
		// leading view does not move — in Bridge Commander that also matches the repository
		// header's, so the section switcher stays put when the section changes.
		.frame(minHeight: 30)
		.padding()
		.windowTitleBarArea()
		.background { instanceShortcuts }
	}

	/// The pages the signed-in user may see: the admin-only ones only for an admin, as in the
	/// console's sidebar. The page on screen stays listed, so the picker never loses its
	/// selection — the page itself says it is not available.
	private var availableTabs: [HomerConsoleReducer.Tab] {
		let isAdmin = store.selectedInstance?.user?.isAdmin == true
		return HomerConsoleReducer.Tab.allCases.filter { !$0.isAdminOnly || isAdmin || $0 == store.tab }
	}

	/// The questions and pending continuations count themselves, as the console's sidebar
	/// badges do.
	private func title(of tab: HomerConsoleReducer.Tab) -> String {
		let count = switch tab {
		case .questions:
			store.selectedInstance?.openQuestionCount ?? 0
		case .continuations:
			store.selectedInstance?.pendingContinuationCount ?? 0
		default:
			0
		}
		return count > 0 ? "\(tab.title) (\(count))" : tab.title
	}

	/// An orange dot on the Questions segment's corner while the instance has open questions.
	/// A segmented picker cannot color one segment (its `NSSegmentedControl` keeps only a plain
	/// label), so the dot is drawn over it — placed by the control's own layout, which gives
	/// every segment an equal share of its width (`fillEqually`).
	@ViewBuilder
	private var openQuestionsDot: some View {
		let tabs = availableTabs
		if (store.selectedInstance?.openQuestionCount ?? 0) > 0, let index = tabs.firstIndex(of: .questions) {
			GeometryReader { proxy in
				let segmentWidth = proxy.size.width / CGFloat(tabs.count)
				Circle()
					.fill(.orange)
					.frame(width: 8, height: 8)
					.position(x: segmentWidth * CGFloat(index + 1) - 7, y: 5)
			}
			.allowsHitTesting(false)
		}
	}

	// MARK: - Instances

	private var instanceMenu: some View {
		HStack(spacing: 6) {
			Menu {
				ForEach(Array(store.instances.enumerated()), id: \.element.id) { index, instance in
					Toggle(isOn: Binding(
						get: { store.addInstance == nil && instance.id == store.selectedInstanceID },
						set: { _ in store.send(.instanceSelected(instance.id)) }
					)) {
						Text(Self.menuTitle(of: instance))
					}
					.keyboardShortcut(Self.shortcutKey(index: index).map { KeyboardShortcut($0, modifiers: .command) })
				}
				Divider()
				Button {
					store.send(.addInstanceTapped)
				} label: {
					Label("Add Instance…", systemImage: "plus")
				}
				if store.addInstance == nil, let instance = store.selectedInstance {
					Button(role: .destructive) {
						store.send(.removeInstanceTapped(instance.id))
					} label: {
						Label(
							"Remove \(HomerEndpoint.displayName(of: instance.baseURL))",
							systemImage: "minus.circle"
						)
					}
				}
			} label: {
				Label(menuLabel, systemImage: "server.rack")
			}
			.labelStyle(.titleAndIcon)
			.menuStyle(.borderlessButton)
			.fixedSize()
			.help("Switch Homer instance (⌘1–⌘9), or add one")

			let elsewhere = store.otherInstancesOpenQuestionCount
			if elsewhere > 0 {
				HomerQuestionCountBadge(count: elsewhere)
					.help("\(elsewhere) open \(elsewhere == 1 ? "question" : "questions") on your other instances")
			}
		}
	}

	private var menuLabel: String {
		guard store.addInstance == nil, let instance = store.selectedInstance else {
			return "New Instance"
		}
		return HomerEndpoint.displayName(of: instance.baseURL)
	}

	/// ⌘1…⌘9, the menu's order. The menu items carry the same shortcuts, but a closed menu does
	/// not answer them reliably; selecting the instance on screen again does nothing, so the
	/// two never fight.
	private var instanceShortcuts: some View {
		ForEach(Array(store.instances.ids.prefix(HomerConsoleReducer.shortcutInstanceLimit).enumerated()), id: \.element) { index, id in
			if let key = Self.shortcutKey(index: index) {
				Button("") { store.send(.instanceSelected(id)) }
					.keyboardShortcut(key, modifiers: .command)
					.hidden()
			}
		}
	}

	private static func shortcutKey(index: Int) -> KeyEquivalent? {
		index < HomerConsoleReducer.shortcutInstanceLimit ? KeyEquivalent(Character(String(index + 1))) : nil
	}

	/// An instance as the menu lists it: its name, who is signed in, and its open questions.
	static func menuTitle(of instance: HomerInstanceReducer.State) -> String {
		let name = HomerEndpoint.displayName(of: instance.baseURL)
		switch instance.session {
		case .checking:
			return "\(name) — connecting…"
		case .signedOut:
			return instance.signIn.sessionExpired ? "\(name) — session expired" : "\(name) — signed out"
		case let .signedIn(user):
			let count = instance.openQuestionCount
			guard count > 0 else {
				return "\(name) — \(user.username)"
			}
			return "\(name) — \(user.username) · \(count) open \(count == 1 ? "question" : "questions")"
		}
	}

	/// Who is signed in, the server's version (the console's corner badge), and Sign Out.
	private func accountMenu(user: HomerUser, instance: HomerInstanceReducer.State) -> some View {
		Menu {
			Text("Signed in as \(user.username)")
			if let version = instance.homerVersion {
				Text("Homer \(version)")
			}
			Divider()
			Button {
				store.send(.instances(.element(id: instance.id, action: .signOutTapped)))
			} label: {
				Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
			}
		} label: {
			Image(systemName: "person.crop.circle")
				.font(.system(size: 16))
				.foregroundStyle(.gray)
		}
		.labelStyle(.titleAndIcon)
		.menuStyle(.borderlessButton)
		.menuIndicator(.hidden)
		.fixedSize()
		.help("Signed in as \(user.username)")
	}

	private func openCurrentPageInWebConsole() {
		store.send(.openWebConsoleTapped(path: store.tab.webConsolePath, title: store.tab.title))
	}
}

/// The selected instance: its sign-in form while signed out, otherwise the page the header's
/// picker chose.
struct HomerInstanceView: View {
	@Bindable
	var store: StoreOf<HomerInstanceReducer>
	let tab: HomerConsoleReducer.Tab

	var body: some View {
		Group {
			switch store.session {
			case .checking:
				ProgressView("Connecting to \(HomerEndpoint.displayName(of: store.baseURL))…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)

			case .signedOut:
				HomerLoginView(store: store.scope(\.signIn, action: \.signIn))

			case let .signedIn(user):
				if tab.isAdminOnly, !user.isAdmin {
					ContentUnavailableView(
						"Admins Only",
						systemImage: "lock",
						description: Text("You don’t have access to this page.")
					)
				}
				else {
					switch tab {
					case .processes:
						HomerProcessListView(store: store)
					case .questions:
						HomerQuestionListView(store: store)
					case .continuations:
						HomerContinuationsView(store: store.scope(\.continuations, action: \.continuations))
					case .schedules:
						HomerSchedulesView(store: store.scope(\.agents, action: \.agents), user: user)
					case .agents:
						HomerAgentsView(store: store.scope(\.agents, action: \.agents), user: user)
					case .costs:
						HomerCostsView(store: store.scope(\.costs, action: \.costs))
					}
				}
			}
		}
		.sheet(item: $store.webPage) { page in
			HomerWebPageView(page: page)
		}
		.sheet(item: $store.scope(\.$processDetail, action: \.processDetail)) { detailStore in
			HomerProcessDetailView(store: detailStore) { processId in
				HomerRunQuestionsView(store: store, processId: processId)
			}
		}
	}
}
