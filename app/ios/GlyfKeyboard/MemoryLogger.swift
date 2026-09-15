import Foundation
import os.log

/// §M0/§10.9: GLYF_MEM lines back the 45 MB extension budget guard, the
/// 6 MB shell budget, and the 4 MB ConnectorSurface budget.
/// Logged at Default level — .info is stream-only and invisible to
/// `log show` after the fact (M0 finding #6).
enum MemoryLogger {
    private static let log = Logger(subsystem: "so.glyf.keyboard", category: "memory")

    /// Physical memory footprint in MB — the number the jetsam limit is enforced against.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576.0
    }

    @discardableResult
    static func logAppearance(_ appearance: Int) -> Double {
        let mb = footprintMB()
        log.log("GLYF_MEM appearance=\(appearance) footprint_mb=\(mb, format: .fixed(precision: 1))")
        return mb
    }

    /// Tagged samples for per-surface budget accounting (shell ≤6 MB, §6.3).
    static func logSurface(_ name: String) {
        let mb = footprintMB()
        log.log("GLYF_MEM surface=\(name, privacy: .public) footprint_mb=\(mb, format: .fixed(precision: 1))")
    }
}
