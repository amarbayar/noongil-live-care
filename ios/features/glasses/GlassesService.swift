import Foundation
import UIKit
import Combine
import MWDATCore

/// Wraps MWDATCore for glasses registration, device management, and URL handling.
@MainActor
final class GlassesService: ObservableObject {
    @Published var registrationState: RegistrationState = .unavailable
    @Published var connectedDeviceIds: [DeviceIdentifier] = []
    @Published var errorMessage: String?
    @Published var configureError: String?
    @Published var cameraPermission: PermissionStatus?

    private var registrationTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?

    var isRegistered: Bool {
        registrationState == .registered
    }

    var hasConnectedDevice: Bool {
        !connectedDeviceIds.isEmpty
    }

    /// Get the first connected Device object
    func firstDevice() -> Device? {
        guard let id = connectedDeviceIds.first else { return nil }
        return Wearables.shared.deviceForIdentifier(id)
    }

    func startObserving() {
        observeRegistrationState()
        observeDevices()
    }

    func stopObserving() {
        registrationTask?.cancel()
        devicesTask?.cancel()
        registrationTask = nil
        devicesTask = nil
    }

    // MARK: - Registration

    func startRegistration() {
        // Check if SDK was configured properly
        if let configErr = configureError {
            errorMessage = configErr
            return
        }

        // Check if Meta AI app is reachable
        let canOpenMetaAI = UIApplication.shared.canOpenURL(URL(string: "fb-viewapp://")!)
        print("[Noongil] Can open Meta AI (fb-viewapp://): \(canOpenMetaAI)")
        print("[Noongil] Registration state before: \(registrationState)")

        errorMessage = nil
        Task {
            do {
                print("[Noongil] Calling startRegistration()...")
                try await Wearables.shared.startRegistration()
                print("[Noongil] startRegistration() succeeded")
            } catch let error as RegistrationError {
                print("[Noongil] RegistrationError: \(error) rawValue=\(error.rawValue)")
                switch error {
                case .alreadyRegistered:
                    errorMessage = "Already registered."
                case .configurationInvalid:
                    if !canOpenMetaAI {
                        errorMessage = "Meta AI app not found. Install 'Meta AI' from the App Store."
                    } else {
                        errorMessage = "Registration failed (configurationInvalid). Did Meta AI app open? Make sure Developer Mode is ON in Meta AI (Settings > App Info > tap version 5x). Error rawValue=\(error.rawValue)"
                    }
                case .metaAINotInstalled:
                    errorMessage = "Meta AI app not installed. Install from App Store."
                case .networkUnavailable:
                    errorMessage = "No internet. Registration requires network."
                case .unknown:
                    errorMessage = "Unknown registration error (rawValue=\(error.rawValue))."
                @unknown default:
                    errorMessage = "Registration error: \(error) rawValue=\(error.rawValue)"
                }
            } catch {
                print("[Noongil] Other error: \(error)")
                errorMessage = "Registration failed: \(error)"
            }
        }
    }

    func startUnregistration() {
        Task {
            do {
                try await Wearables.shared.startUnregistration()
                errorMessage = nil
            } catch {
                errorMessage = "Unregistration failed: \(error.localizedDescription)"
            }
        }
    }

    func handleUrl(_ url: URL) async {
        do {
            let handled = try await Wearables.shared.handleUrl(url)
            print("[Noongil] handleUrl result: \(handled)")
            // Re-check camera permission after returning from Meta AI
            await checkCameraPermission()
        } catch {
            errorMessage = "URL handling failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Camera Permission

    /// Check current camera permission status.
    func checkCameraPermission() async {
        do {
            let status = try await Wearables.shared.checkPermissionStatus(.camera)
            cameraPermission = status
            print("[Noongil] Camera permission: \(status)")
        } catch {
            print("[Noongil] checkPermissionStatus failed: \(error)")
            cameraPermission = nil
        }
    }

    /// Request camera permission via Meta AI app.
    /// This opens Meta AI; the user grants access there, then returns via deep link.
    func requestCameraPermission() async {
        do {
            print("[Noongil] Requesting camera permission...")
            let status = try await Wearables.shared.requestPermission(.camera)
            cameraPermission = status
            print("[Noongil] Camera permission result: \(status)")
        } catch {
            print("[Noongil] requestPermission failed: \(error)")
            errorMessage = "Camera permission request failed: \(error)"
        }
    }

    // MARK: - Observation Streams

    private func observeRegistrationState() {
        registrationTask = Task { [weak self] in
            for await state in Wearables.shared.registrationStateStream() {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.registrationState = state
                }
            }
        }
    }

    private func observeDevices() {
        devicesTask = Task { [weak self] in
            for await deviceIds in Wearables.shared.devicesStream() {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.connectedDeviceIds = deviceIds
                }
            }
        }
    }
}
