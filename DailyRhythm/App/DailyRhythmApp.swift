import SwiftUI
import UIKit

@main
struct DailyRhythmApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var setup = OnboardingPreferences()

    var body: some Scene {
        WindowGroup {
            RhythmRootView()
                .environmentObject(model)
                .environmentObject(setup)
                .tint(RhythmTheme.coral)
        }
    }
}

private struct RhythmRootView: View {
    @ObservedObject private var navigation = RhythmNavigation.shared
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var setup: OnboardingPreferences
    @State private var checkedFirstRun = false
    @State private var showingSetup = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack { TodayView() }
                .id(navigation.todayRoute)
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(0)
            NavigationStack { HabitsView() }
                .tabItem { Label("Habits", systemImage: "square.stack.3d.up") }
                .tag(1)
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "chart.bar.xaxis") }
                .tag(2)
        }
        .onOpenURL { url in
            guard url == RhythmSurfaceRefresh.todayURL else { return }
            navigation.openToday()
        }
        .onChange(of: navigation.todayRoute) { _, _ in
            showingSetup = false
            model.refresh()
        }
        .sheet(isPresented: $showingSetup) { OnboardingView() }
        .onChange(of: model.refreshedAt, initial: true) { _, _ in
            guard !checkedFirstRun, model.today != nil else { return }
            checkedFirstRun = true
            if !model.habits.isEmpty { setup.finish() }
            else if setup.loadError == nil && setup.progress.shouldOfferAutomatically(hasExistingHabits: false) {
                setup.begin()
                showingSetup = true
            }
        }
        .foregroundStyle(RhythmTheme.ink)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = model.loadError {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your rhythm couldn't be refreshed.")
                            .font(.subheadline.weight(.semibold))
                        Text(error).font(.caption)
                    }
                    Spacer(minLength: 0)
                    Button("Retry") { model.refresh() }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .foregroundStyle(RhythmTheme.ink)
                .padding(16)
                .background(RhythmTheme.card)
            }
        }
        .alert("We couldn't save that change", isPresented: Binding(
            get: { model.operationError != nil },
            set: { if !$0 { model.operationError = nil } }
        )) {
            Button("OK", role: .cancel) { model.operationError = nil }
        } message: {
            Text(model.operationError ?? "Please try again. Your existing data has been kept.")
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            #if DEBUG && DAILY_RHYTHM_SCHEMA_SPIKE && compiler(>=6.4)
            if #available(iOS 27.0, *) { await ReminderSchemaSmoke.runIfRequested() }
            #endif
            model.refresh()
            #if DAILY_RHYTHM_SCHEMA_SPIKE && compiler(>=6.4)
            if #available(iOS 27.0, *) { await ReminderSchemaIndex.shared.refreshAfterMutation() }
            #endif
            // Extension writes and local midnight can happen without an app event.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                model.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            model.refresh()
        }
    }
}
