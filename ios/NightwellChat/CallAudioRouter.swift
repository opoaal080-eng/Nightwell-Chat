import Foundation
import AVFoundation
import Combine

struct CallAudioDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

/// Route choices compatible with the voice-chat input/output session.
/// Bluetooth HFP and wired/USB headsets appear only when connected.
@MainActor final class CallAudioRouter: ObservableObject {
    @Published private(set) var devices: [CallAudioDevice] = []
    @Published private(set) var selected = "receiver"
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
        reload()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func reload() {
        let session = AVAudioSession.sharedInstance()
        var choices = [
            CallAudioDevice(id: "receiver", name: "Разговорный динамик"),
            CallAudioDevice(id: "speaker", name: "Громкая связь")
        ]
        for port in session.availableInputs ?? [] {
            switch port.portType {
            case .bluetoothHFP, .headsetMic, .usbAudio:
                choices.append(CallAudioDevice(id: port.uid, name: port.portName))
            default: break
            }
        }
        devices = choices
        if session.currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker }) {
            selected = "speaker"
        } else if let input = session.currentRoute.inputs.first,
                  choices.contains(where: { $0.id == input.uid && $0.id != "receiver" }) {
            selected = input.uid
        } else {
            selected = "receiver"
        }
    }

    func select(_ id: String) {
        let session = AVAudioSession.sharedInstance()
        do {
            if id == "speaker" {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
                let target = id == "receiver"
                    ? session.availableInputs?.first(where: { $0.portType == .builtInMic })
                    : session.availableInputs?.first(where: { $0.uid == id })
                if let target { try session.setPreferredInput(target) }
            }
            selected = id
            reload()
        } catch {
            NSLog("Nightwell audio route change failed: %@", error.localizedDescription)
            reload()
        }
    }
}
