import Foundation
import CallKit
import AVFoundation

/// Native iOS call UI for Nightwell Chat. The WebRTC transport is still in
/// WKWebView; CallKit does not by itself make WebKit microphone capture run
/// while the device is locked.
final class CallKitCoordinator: NSObject, CXProviderDelegate {
    static let shared = CallKitCoordinator()

    private let provider: CXProvider
    private let controller = CXCallController()
    private var uuidsByCallID: [String: UUID] = [:]
    private var callIDsByUUID: [UUID: String] = [:]
    private var outgoingIDs = Set<String>()
    private var connectedIDs = Set<String>()

    /// Assigned once by ChatStore. Invoked on the main dispatch queue.
    var onAnswer: ((String) -> Void)?
    var onEnd: ((String) -> Void)?
    var onMute: ((String, Bool) -> Void)?

    private override init() {
        let config = CXProviderConfiguration(localizedName: "Nightwell Chat")
        config.supportsVideo = false
        config.supportedHandleTypes = [.generic]
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.includesCallsInRecents = true
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    func reportIncoming(callID: String, callerName: String) {
        guard uuidsByCallID[callID] == nil else { return }
        let uuid = UUID()
        add(callID: callID, uuid: uuid)
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            guard let error else { return }
            NSLog("Nightwell CallKit: incoming call not shown: %@", error.localizedDescription)
            DispatchQueue.main.async {
                if self?.uuidsByCallID[callID] == uuid {
                    self?.remove(callID: callID)
                }
            }
        }
    }

    func reportOutgoing(callID: String, displayName: String) {
        guard uuidsByCallID[callID] == nil else { return }
        let uuid = UUID()
        add(callID: callID, uuid: uuid)
        outgoingIDs.insert(callID)
        let handle = CXHandle(type: .generic, value: displayName)
        let start = CXStartCallAction(call: uuid, handle: handle)
        start.isVideo = false
        controller.request(CXTransaction(action: start)) { [weak self] error in
            if let error {
                NSLog("Nightwell CallKit: outgoing call not shown: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    if self?.uuidsByCallID[callID] == uuid {
                        self?.remove(callID: callID)
                    }
                }
            }
        }
    }

    func reportConnected(callID: String) {
        guard outgoingIDs.contains(callID),
              let uuid = uuidsByCallID[callID],
              connectedIDs.insert(callID).inserted else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    @discardableResult
    func requestAnswer(callID: String) -> Bool {
        guard let uuid = uuidsByCallID[callID] else { return false }
        controller.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { error in
            if let error { NSLog("Nightwell CallKit: answer failed: %@", error.localizedDescription) }
        }
        return true
    }

    func requestMute(callID: String, muted: Bool) {
        guard let uuid = uuidsByCallID[callID] else {
            onMute?(callID, muted)
            return
        }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: muted))) { [weak self] error in
            if let error {
                NSLog("Nightwell CallKit: mute action failed: %@", error.localizedDescription)
                DispatchQueue.main.async { self?.onMute?(callID, muted) }
            }
        }
    }

    func requestEnd(callID: String) {
        guard let uuid = uuidsByCallID[callID] else {
            onEnd?(callID)
            return
        }
        controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
            guard let error else { return }
            NSLog("Nightwell CallKit: end action failed: %@", error.localizedDescription)
            DispatchQueue.main.async {
                self?.reportEnded(callID: callID, reason: .failed)
                self?.onEnd?(callID)
            }
        }
    }

    func reportEnded(callID: String, reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = uuidsByCallID[callID] else { return }
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        remove(callID: callID)
    }

    private func add(callID: String, uuid: UUID) {
        uuidsByCallID[callID] = uuid
        callIDsByUUID[uuid] = callID
    }

    private func remove(callID: String) {
        if let uuid = uuidsByCallID.removeValue(forKey: callID) {
            callIDsByUUID.removeValue(forKey: uuid)
        }
        outgoingIDs.remove(callID)
        connectedIDs.remove(callID)
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                                         options: [.allowBluetooth])
            // The operating system activates CallKit's session; do not force
            // setActive(true) here and fight the system's audio arbitration.
        } catch {
            NSLog("Nightwell CallKit audio setup: %@", error.localizedDescription)
        }
    }

    func providerDidReset(_ provider: CXProvider) {
        let callIDs = Array(uuidsByCallID.keys)
        uuidsByCallID.removeAll()
        callIDsByUUID.removeAll()
        outgoingIDs.removeAll()
        connectedIDs.removeAll()
        for callID in callIDs { onEnd?(callID) }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        configureAudioSession()
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let callID = callIDsByUUID[action.callUUID] else {
            action.fail()
            return
        }
        configureAudioSession()
        action.fulfill()
        onAnswer?(callID)
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let callID = callIDsByUUID[action.callUUID] else {
            action.fulfill()
            return
        }
        remove(callID: callID)
        action.fulfill()
        onEnd?(callID)
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let callID = callIDsByUUID[action.callUUID] else {
            action.fail()
            return
        }
        onMute?(callID, action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // Native WebRTC will use this callback to start its audio device in
        // the future. WKWebView audio cannot be activated here directly.
    }
}
