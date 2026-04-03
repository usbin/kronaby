import CoreBluetooth

enum BLEConstants {
    // Scan filter UUIDs
    static let kronabyAdvertisementUUID = CBUUID(string: "F431")
    static let hidServiceUUID = CBUUID(string: "1812")

    // Anima custom service
    static let animaServiceUUID = CBUUID(string: "6e406d41-b5a3-f393-e0a9-e6414d494e41")
    static let commandCharUUID = CBUUID(string: "6e401980-b5a3-f393-e0a9-e6414d494e41")
    static let notifyCharUUID  = CBUUID(string: "6e401981-b5a3-f393-e0a9-e6414d494e41")

    // Device Information Service
    static let deviceInfoServiceUUID = CBUUID(string: "180A")

    // Nordic DFU
    static let dfuServiceUUID = CBUUID(string: "00001530-1212-efde-1523-785feabcd123")
}
