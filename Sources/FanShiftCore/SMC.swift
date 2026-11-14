import CSMC
import Foundation

public struct SMCError: Error, CustomStringConvertible {
    public let op: String
    public let key: String
    public let kr: Int32
    public let result: UInt8
    public var note: String = ""

    /// 内核返回 kIOReturnNotPrivileged：写风扇键需要 root
    public var isNotPrivileged: Bool { UInt32(bitPattern: kr) == 0xe000_02c1 }

    public var description: String {
        var s = "SMC \(op) \(key) 失败"
        if kr != 0 { s += String(format: " kr=0x%x", UInt32(bitPattern: kr)) }
        if result != 0 { s += String(format: " result=0x%02x", result) }
        if isNotPrivileged { s += "（没有权限，需要 root）" }
        if result == 0x82 { s += "（固件拒绝）" }
        if result == 0x84 { s += "（没有这个键）" }
        if !note.isEmpty { s += " \(note)" }
        return s
    }
}

/// AppleSMC 键值读写。读不需要权限，写风扇相关的键需要 root。
public enum SMC {
    public struct KeyInfo {
        public let size: Int
        public let type: String
    }

    static func code(_ key: String) -> UInt32 {
        precondition(key.utf8.count == 4, "SMC 键必须是 4 个字符：\(key)")
        return key.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func string(_ code: UInt32) -> String {
        let bytes = [UInt8(code >> 24 & 0xff), UInt8(code >> 16 & 0xff), UInt8(code >> 8 & 0xff), UInt8(code & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    /// 键不存在时返回 nil
    public static func info(_ key: String) -> KeyInfo? {
        var ki = csmc_keyinfo()
        let st = csmc_key_info(code(key), &ki)
        guard st.kr == 0, st.result == 0 else { return nil }
        return KeyInfo(size: Int(ki.size), type: string(ki.type))
    }

    public static func read(_ key: String) throws -> (type: String, bytes: [UInt8]) {
        var ki = csmc_keyinfo()
        var buf = [UInt8](repeating: 0, count: 32)
        let st = csmc_read(code(key), &ki, &buf)
        guard st.kr == 0, st.result == 0 else {
            throw SMCError(op: "读", key: key, kr: st.kr, result: st.result)
        }
        return (string(ki.type), Array(buf.prefix(Int(min(ki.size, 32)))))
    }

    /// 把常见数值类型统一读成 Double
    public static func readDouble(_ key: String) throws -> Double {
        let (type, b) = try read(key)
        switch type {
        case "flt " where b.count == 4:
            let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui8 " where b.count >= 1, "flag" where b.count >= 1:
            return Double(b[0])
        case "ui16" where b.count == 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32" where b.count == 4:
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        case "fpe2" where b.count == 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4.0
        default:
            throw SMCError(op: "读", key: key, kr: 0, result: 0, note: "不认识的类型 \(type)")
        }
    }

    /// 写之前核对键的类型和长度，对不上就不写
    private static func write(_ key: String, expecting type: String, bytes: [UInt8]) throws {
        guard let ki = info(key) else {
            throw SMCError(op: "写", key: key, kr: 0, result: 0x84)
        }
        guard ki.type == type, ki.size == bytes.count else {
            throw SMCError(op: "写", key: key, kr: 0, result: 0,
                           note: "类型不符：期望 \(type)/\(bytes.count) 字节，实际 \(ki.type)/\(ki.size) 字节")
        }
        let st = bytes.withUnsafeBufferPointer { csmc_write(code(key), $0.baseAddress, UInt32(bytes.count)) }
        guard st.kr == 0, st.result == 0 else {
            throw SMCError(op: "写", key: key, kr: st.kr, result: st.result)
        }
    }

    public static func writeFloat(_ key: String, _ value: Float) throws {
        let bits = value.bitPattern
        let bytes = [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]
        try write(key, expecting: "flt ", bytes: bytes)
    }

    public static func writeUInt8(_ key: String, _ value: UInt8) throws {
        try write(key, expecting: "ui8 ", bytes: [value])
    }
}
