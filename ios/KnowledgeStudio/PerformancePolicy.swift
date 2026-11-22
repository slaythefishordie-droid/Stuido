import Combine
import KnowledgeCore
import Observation
import UIKit

/// One process-wide source of resource policy. No polling and no change to display
/// refresh rate, text resolution, core animations or user-visible capabilities.
@MainActor
@Observable
final class PerformancePolicy {
    static let shared = PerformancePolicy()
    private(set) var budget = PerformanceBudget(lowPower: false, thermal: .nominal)
    @ObservationIgnored private var observers: Set<AnyCancellable> = []
    @ObservationIgnored private var memoryPressure = false

    private init() {
        refresh()
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange,
            ProcessInfo.thermalStateDidChangeNotification, UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        if name == UIApplication.didBecomeActiveNotification { self?.memoryPressure = false }
                        self?.refresh()
                    }
                }.store(in: &observers)
        }
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.memoryPressure = true
                    self?.refresh()
                    StudyThumbnails.releaseMemory()
                }
            }.store(in: &observers)
    }

    private func refresh() {
        let thermal: PerformanceBudget.ThermalPressure
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .serious
        }
        budget = PerformanceBudget(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermal: thermal, memoryPressure: memoryPressure)
        StudyThumbnails.apply(budget)
    }
}
