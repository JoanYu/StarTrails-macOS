import Foundation
import Darwin

@MainActor
class ResourceMonitor: ObservableObject, @unchecked Sendable {
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Double = 0.0 // in MB
    @Published var totalMemory: Double = 0.0 // in MB
    
    private var timer: Timer?
    
    private var previousInfo: host_cpu_load_info = host_cpu_load_info()
    
    init() {
        let hostPort = mach_host_self()
        var size = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        var hostInfo = host_basic_info()
        
        let result = withUnsafeMutablePointer(to: &hostInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_info(hostPort, HOST_BASIC_INFO, $0, &size)
            }
        }
        
        if result == KERN_SUCCESS {
            self.totalMemory = Double(hostInfo.max_mem) / (1024 * 1024)
        }
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateUsage()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateUsage() {
        // Memory
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            self.memoryUsage = Double(taskInfo.resident_size) / (1024 * 1024)
        }
        
        // CPU
        let hostPort = mach_host_self()
        var cpuInfo = host_cpu_load_info()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        
        let cpuResult = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        
        if cpuResult == KERN_SUCCESS {
            let userDiff = Double(cpuInfo.cpu_ticks.0 - previousInfo.cpu_ticks.0)
            let sysDiff  = Double(cpuInfo.cpu_ticks.1 - previousInfo.cpu_ticks.1)
            let idleDiff = Double(cpuInfo.cpu_ticks.2 - previousInfo.cpu_ticks.2)
            let niceDiff = Double(cpuInfo.cpu_ticks.3 - previousInfo.cpu_ticks.3)
            
            let totalTicks = userDiff + sysDiff + idleDiff + niceDiff
            if totalTicks > 0 {
                self.cpuUsage = ((totalTicks - idleDiff) / totalTicks) * 100.0
            }
            previousInfo = cpuInfo
        }
    }
}
