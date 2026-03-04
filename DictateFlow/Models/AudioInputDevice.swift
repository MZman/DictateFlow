import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let deviceID: UInt32
}
