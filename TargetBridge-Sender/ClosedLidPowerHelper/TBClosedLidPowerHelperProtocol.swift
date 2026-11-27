import Foundation

@objc protocol TBClosedLidPowerHelperProtocol {
    func beginSession(identifier: String, withReply reply: @escaping (Bool, String?) -> Void)
    func heartbeat(identifier: String, withReply reply: @escaping (Bool, String?) -> Void)
    func endSession(identifier: String, withReply reply: @escaping (Bool, String?) -> Void)
    func status(withReply reply: @escaping (String) -> Void)
}
