import Foundation
import MessagePack

struct ButtonEvent: Equatable {
    let button: Int    // 0=top, 1=crown, 2=bottom
    let eventType: Int // 1=single, 2=long start, 3=double, etc.

    var buttonName: String {
        switch button {
        case 0: return "상단"
        case 1: return "크라운"
        case 2: return "하단"
        default: return "알 수 없음"
        }
    }

    var eventName: String {
        switch eventType {
        case 1: return "1회 클릭"
        case 2: return "길게 누름"
        case 3: return "2회 클릭"
        case 4: return "3회 클릭"
        case 5: return "4회 클릭"
        case 6: return "1회+길게"
        case 7: return "2회+길게"
        case 8: return "3회+길게"
        case 11: return "폰 찾기"
        case 12: return "길게 누름 끝"
        default: return "코드 \(eventType)"
        }
    }
}

final class KronabyProtocol {
    func encode(commandId: Int, value: Any) -> Data {
        let msgValue = convertToMessagePackValue(value)
        let map: MessagePackValue = .map([.int(Int64(commandId)): msgValue])
        return pack(map)
    }

    func decode(data: Data) -> Any? {
        guard let unpacked = try? unpack(data) else { return nil }
        return convertFromMessagePackValue(unpacked.value)
    }

    func parseButtonEvent(_ decoded: Any?, commandMap: [String: Int]) -> ButtonEvent? {
        guard let dict = decoded as? [Int: Any],
              let buttonCmdId = commandMap["button"],
              let arr = dict[buttonCmdId] as? [Int],
              arr.count >= 2 else { return nil }
        return ButtonEvent(button: arr[0], eventType: arr[1])
    }

    // MARK: - MessagePack Helpers

    private func convertToMessagePackValue(_ value: Any) -> MessagePackValue {
        switch value {
        case let i as Int:
            return .int(Int64(i))
        case let s as String:
            return .string(s)
        case let b as Bool:
            return .bool(b)
        case let arr as [Any]:
            return .array(arr.map { convertToMessagePackValue($0) })
        case let dict as [Int: Any]:
            var map: [MessagePackValue: MessagePackValue] = [:]
            for (k, v) in dict {
                map[.int(Int64(k))] = convertToMessagePackValue(v)
            }
            return .map(map)
        default:
            return .nil
        }
    }

    private func convertFromMessagePackValue(_ value: MessagePackValue) -> Any? {
        switch value {
        case .int(let i): return Int(i)
        case .uint(let u): return Int(u)
        case .string(let s): return s
        case .bool(let b): return b
        case .float(let f): return f
        case .double(let d): return d
        case .array(let arr): return arr.compactMap { convertFromMessagePackValue($0) }
        case .map(let map):
            // Try to return as [String: Int] for command map, otherwise [Int: Any]
            var stringDict: [String: Int] = [:]
            var intDict: [Int: Any] = [:]
            var isStringKeyed = true

            for (k, v) in map {
                if case .string(let key) = k, case .int(let val) = v {
                    stringDict[key] = Int(val)
                } else {
                    isStringKeyed = false
                }
                if case .int(let key) = k {
                    intDict[Int(key)] = convertFromMessagePackValue(v)
                } else if case .uint(let key) = k {
                    intDict[Int(key)] = convertFromMessagePackValue(v)
                }
            }
            return isStringKeyed && !stringDict.isEmpty ? stringDict : intDict
        case .nil: return nil
        default: return nil
        }
    }
}
