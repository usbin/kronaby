import Foundation

// Minimal MsgPack encoder/decoder for Kronaby BLE protocol.
// Only supports the subset Kronaby uses: int, bool, string, array, map, nil.

enum MsgPackValue: Equatable {
    case int(Int64)
    case uint(UInt64)
    case bool(Bool)
    case string(String)
    case array([MsgPackValue])
    case map([(key: MsgPackValue, value: MsgPackValue)])
    case `nil`

    static func == (lhs: MsgPackValue, rhs: MsgPackValue) -> Bool {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return a == b
        case (.uint(let a), .uint(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.nil, .nil): return true
        case (.array(let a), .array(let b)): return a == b
        case (.map(let a), .map(let b)):
            guard a.count == b.count else { return false }
            for (pa, pb) in zip(a, b) {
                if pa.key != pb.key || pa.value != pb.value { return false }
            }
            return true
        default: return false
        }
    }
}

// MARK: - Encoder

enum MsgPackEncoder {
    static func encode(_ value: MsgPackValue) -> Data {
        var data = Data()
        write(value, to: &data)
        return data
    }

    private static func write(_ value: MsgPackValue, to data: inout Data) {
        switch value {
        case .nil:
            data.append(0xC0)

        case .bool(let b):
            data.append(b ? 0xC3 : 0xC2)

        case .int(let i):
            if i >= 0 && i <= 127 {
                data.append(UInt8(i))
            } else if i >= -32 && i < 0 {
                data.append(UInt8(bitPattern: Int8(i)))
            } else if i >= Int64(Int8.min) && i <= Int64(Int8.max) {
                data.append(0xD0)
                data.append(UInt8(bitPattern: Int8(i)))
            } else if i >= Int64(Int16.min) && i <= Int64(Int16.max) {
                data.append(0xD1)
                var be = Int16(i).bigEndian
                data.append(Data(bytes: &be, count: 2))
            } else if i >= Int64(Int32.min) && i <= Int64(Int32.max) {
                data.append(0xD2)
                var be = Int32(i).bigEndian
                data.append(Data(bytes: &be, count: 4))
            } else {
                data.append(0xD3)
                var be = i.bigEndian
                data.append(Data(bytes: &be, count: 8))
            }

        case .uint(let u):
            if u <= 127 {
                data.append(UInt8(u))
            } else if u <= UInt64(UInt8.max) {
                data.append(0xCC)
                data.append(UInt8(u))
            } else if u <= UInt64(UInt16.max) {
                data.append(0xCD)
                var be = UInt16(u).bigEndian
                data.append(Data(bytes: &be, count: 2))
            } else if u <= UInt64(UInt32.max) {
                data.append(0xCE)
                var be = UInt32(u).bigEndian
                data.append(Data(bytes: &be, count: 4))
            } else {
                data.append(0xCF)
                var be = u.bigEndian
                data.append(Data(bytes: &be, count: 8))
            }

        case .string(let s):
            let utf8 = Array(s.utf8)
            let count = utf8.count
            if count <= 31 {
                data.append(0xA0 | UInt8(count))
            } else if count <= 0xFF {
                data.append(0xD9)
                data.append(UInt8(count))
            } else if count <= 0xFFFF {
                data.append(0xDA)
                var be = UInt16(count).bigEndian
                data.append(Data(bytes: &be, count: 2))
            } else {
                data.append(0xDB)
                var be = UInt32(count).bigEndian
                data.append(Data(bytes: &be, count: 4))
            }
            data.append(contentsOf: utf8)

        case .array(let arr):
            let count = arr.count
            if count <= 15 {
                data.append(0x90 | UInt8(count))
            } else if count <= 0xFFFF {
                data.append(0xDC)
                var be = UInt16(count).bigEndian
                data.append(Data(bytes: &be, count: 2))
            } else {
                data.append(0xDD)
                var be = UInt32(count).bigEndian
                data.append(Data(bytes: &be, count: 4))
            }
            for item in arr { write(item, to: &data) }

        case .map(let pairs):
            let count = pairs.count
            if count <= 15 {
                data.append(0x80 | UInt8(count))
            } else if count <= 0xFFFF {
                data.append(0xDE)
                var be = UInt16(count).bigEndian
                data.append(Data(bytes: &be, count: 2))
            } else {
                data.append(0xDF)
                var be = UInt32(count).bigEndian
                data.append(Data(bytes: &be, count: 4))
            }
            for pair in pairs {
                write(pair.key, to: &data)
                write(pair.value, to: &data)
            }
        }
    }
}

// MARK: - Decoder

enum MsgPackDecoder {
    struct Stream {
        let data: Data
        var offset: Int = 0

        var remaining: Int { data.count - offset }

        mutating func readByte() -> UInt8? {
            guard offset < data.count else { return nil }
            let b = data[offset]
            offset += 1
            return b
        }

        mutating func readBytes(_ count: Int) -> Data? {
            guard offset + count <= data.count else { return nil }
            let slice = data[offset..<offset+count]
            offset += count
            return Data(slice)
        }

        mutating func readUInt16() -> UInt16? {
            guard let bytes = readBytes(2) else { return nil }
            return bytes.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        }

        mutating func readUInt32() -> UInt32? {
            guard let bytes = readBytes(4) else { return nil }
            return bytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        }

        mutating func readUInt64() -> UInt64? {
            guard let bytes = readBytes(8) else { return nil }
            return bytes.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        }
    }

    static func decode(_ data: Data) -> MsgPackValue? {
        var stream = Stream(data: data)
        return readValue(&stream)
    }

    private static func readValue(_ s: inout Stream) -> MsgPackValue? {
        guard let b = s.readByte() else { return nil }

        switch b {
        // nil
        case 0xC0: return .nil
        // bool
        case 0xC2: return .bool(false)
        case 0xC3: return .bool(true)

        // positive fixint (0x00-0x7F)
        case 0x00...0x7F:
            return .int(Int64(b))

        // negative fixint (0xE0-0xFF)
        case 0xE0...0xFF:
            return .int(Int64(Int8(bitPattern: b)))

        // uint8
        case 0xCC:
            guard let v = s.readByte() else { return nil }
            return .uint(UInt64(v))
        // uint16
        case 0xCD:
            guard let v = s.readUInt16() else { return nil }
            return .uint(UInt64(v))
        // uint32
        case 0xCE:
            guard let v = s.readUInt32() else { return nil }
            return .uint(UInt64(v))
        // uint64
        case 0xCF:
            guard let v = s.readUInt64() else { return nil }
            return .uint(v)

        // int8
        case 0xD0:
            guard let v = s.readByte() else { return nil }
            return .int(Int64(Int8(bitPattern: v)))
        // int16
        case 0xD1:
            guard let v = s.readUInt16() else { return nil }
            return .int(Int64(Int16(bitPattern: v)))
        // int32
        case 0xD2:
            guard let v = s.readUInt32() else { return nil }
            return .int(Int64(Int32(bitPattern: v)))
        // int64
        case 0xD3:
            guard let v = s.readUInt64() else { return nil }
            return .int(Int64(bitPattern: v))

        // fixstr (0xA0-0xBF)
        case 0xA0...0xBF:
            let count = Int(b & 0x1F)
            return readString(&s, count: count)
        // str8
        case 0xD9:
            guard let len = s.readByte() else { return nil }
            return readString(&s, count: Int(len))
        // str16
        case 0xDA:
            guard let len = s.readUInt16() else { return nil }
            return readString(&s, count: Int(len))
        // str32
        case 0xDB:
            guard let len = s.readUInt32() else { return nil }
            return readString(&s, count: Int(len))

        // fixarray (0x90-0x9F)
        case 0x90...0x9F:
            let count = Int(b & 0x0F)
            return readArray(&s, count: count)
        // array16
        case 0xDC:
            guard let count = s.readUInt16() else { return nil }
            return readArray(&s, count: Int(count))
        // array32
        case 0xDD:
            guard let count = s.readUInt32() else { return nil }
            return readArray(&s, count: Int(count))

        // fixmap (0x80-0x8F)
        case 0x80...0x8F:
            let count = Int(b & 0x0F)
            return readMap(&s, count: count)
        // map16
        case 0xDE:
            guard let count = s.readUInt16() else { return nil }
            return readMap(&s, count: Int(count))
        // map32
        case 0xDF:
            guard let count = s.readUInt32() else { return nil }
            return readMap(&s, count: Int(count))

        // bin8/16/32 — skip binary data
        case 0xC4:
            guard let len = s.readByte() else { return nil }
            _ = s.readBytes(Int(len))
            return .nil
        case 0xC5:
            guard let len = s.readUInt16() else { return nil }
            _ = s.readBytes(Int(len))
            return .nil
        case 0xC6:
            guard let len = s.readUInt32() else { return nil }
            _ = s.readBytes(Int(len))
            return .nil

        default:
            return nil
        }
    }

    private static func readString(_ s: inout Stream, count: Int) -> MsgPackValue? {
        guard let bytes = s.readBytes(count) else { return nil }
        guard let str = String(data: bytes, encoding: .utf8) else { return nil }
        return .string(str)
    }

    private static func readArray(_ s: inout Stream, count: Int) -> MsgPackValue? {
        var arr: [MsgPackValue] = []
        arr.reserveCapacity(count)
        for _ in 0..<count {
            guard let v = readValue(&s) else { return nil }
            arr.append(v)
        }
        return .array(arr)
    }

    private static func readMap(_ s: inout Stream, count: Int) -> MsgPackValue? {
        var pairs: [(key: MsgPackValue, value: MsgPackValue)] = []
        pairs.reserveCapacity(count)
        for _ in 0..<count {
            guard let k = readValue(&s), let v = readValue(&s) else { return nil }
            pairs.append((key: k, value: v))
        }
        return .map(pairs)
    }
}
