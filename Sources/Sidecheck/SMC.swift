import IOKit

/// Minimal read-only AppleSMC client for CPU temperature. Talks to the
/// AppleSMC IOService directly — a local, permission-free read (the same
/// technique iStat Menus and Stats use). Only decodes the value types that
/// temperature keys actually use.
enum SMCTemp {
    /// Known CPU-temperature keys across Apple Silicon and Intel Macs; the
    /// first one that answers with a plausible value wins.
    private static let preferredKeys = [
        "Tp09", "Tp01", "Tp05", "Tp04", "Tp03", "Tp02", // Apple Silicon performance cores
        "TC0P", "TC0E", "TC0F", "TC0D", "TC0H", "TCD0P", // Intel CPU proximity / die
    ]

    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        // UInt32, not IOByteCount — the imported typedef is wider on Swift
        // and breaks the kernel's exact 80-byte struct layout.
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private typealias SMCBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    /// Mirrors the kernel's SMCKeyData struct (80 bytes) — field order and
    /// padding matter for IOConnectCallStructMethod.
    private struct SMCKeyData {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        // C rounds SMCKeyInfoData's 9 bytes up to its 12-byte stride before
        // the next member; Swift packs tighter, so pad explicitly.
        var keyInfoPadding: (UInt8, UInt8, UInt8) = (0, 0, 0)
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes = SMCBytes(
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    // Kernel conventions (osx-cpu-temp): selector 2 with a subcommand in data8.
    private static let kernelIndexSMC: UInt32 = 2
    private static let smcCmdReadBytes: UInt8 = 5
    private static let smcCmdReadKeyInfo: UInt8 = 9

    /// Connection opened once and kept for the app's lifetime.
    private static let connection: io_connect_t? = {
        guard MemoryLayout<SMCKeyData>.size == 80 else {
            fputs("[Sidecheck] SMC struct layout mismatch — temperature disabled\n", stderr)
            return nil
        }
        var service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connect) == KERN_SUCCESS else { return nil }
        return connect
    }()

    /// CPU temperature in °C, or nil when no known sensor answers.
    static func cpuTemperature() -> Double? {
        guard let connection else { return nil }
        for key in preferredKeys {
            if let value = readTemperature(connection: connection, key: key), (15...125).contains(value) {
                return value
            }
        }
        return nil
    }

    // MARK: - Plumbing

    private static func readTemperature(connection: io_connect_t, key: String) -> Double? {
        guard let info = call(connection: connection, key: key, command: smcCmdReadKeyInfo) else { return nil }
        let size = min(Int(info.keyInfo.dataSize), 32)
        guard size > 0 else { return nil }

        guard let reply = call(
            connection: connection,
            key: key,
            command: smcCmdReadBytes,
            dataSize: info.keyInfo.dataSize
        ) else { return nil }

        let bytes: [UInt8] = withUnsafePointer(to: reply.bytes) { pointer in
            let raw = UnsafeRawPointer(pointer)
            return (0..<size).map { raw.load(fromByteOffset: $0, as: UInt8.self) }
        }
        return decode(type: info.keyInfo.dataType, bytes: bytes)
    }

    private static func call(connection: io_connect_t, key: String, command: UInt8, dataSize: UInt32 = 0) -> SMCKeyData? {
        var input = SMCKeyData()
        input.key = packedKey(key)
        input.data8 = command
        input.keyInfo.dataSize = dataSize

        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(
            connection, kernelIndexSMC,
            &input, MemoryLayout<SMCKeyData>.size,
            &output, &outputSize
        )
        guard kr == KERN_SUCCESS, output.result == 0 else { return nil } // 0 = kSMCSuccess
        return output
    }

    /// Four-character SMC key packed big-endian ("TC0P" → UInt32).
    private static func packedKey(_ name: String) -> UInt32 {
        let bytes = Array(name.utf8.prefix(4))
        guard bytes.count == 4 else { return 0 }
        return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }

    private static func decode(type: UInt32, bytes: [UInt8]) -> Double? {
        let typeName = String(decoding: [
            UInt8(truncatingIfNeeded: type >> 24),
            UInt8(truncatingIfNeeded: type >> 16),
            UInt8(truncatingIfNeeded: type >> 8),
            UInt8(truncatingIfNeeded: type),
        ], as: UTF8.self)

        switch typeName {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case "ui8":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        default:
            return nil
        }
    }
}
