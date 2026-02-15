import AVFoundation
import CoreImage

public final class CameraCapture: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var session: AVCaptureSession?
    private var continuation: CheckedContinuation<CMSampleBuffer, Error>?
    private var frameCount = 0
    private let warmupFrames = 30

    public override init() {
        super.init()
    }

    public func captureFrame(deviceID: String? = nil) async throws -> CMSampleBuffer {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        let device: AVCaptureDevice?
        if let deviceID = deviceID {
            device = AVCaptureDevice(uniqueID: deviceID)
        } else {
            device = AVCaptureDevice.default(for: .video)
        }

        guard let camera = device else {
            throw StraightenUpError.noCameraFound
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw StraightenUpError.cameraSetupFailed("Cannot add camera input")
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let queue = DispatchQueue(label: "com.straightenup.camera")
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            throw StraightenUpError.cameraSetupFailed("Cannot add video output")
        }
        session.addOutput(output)

        self.session = session
        self.frameCount = 0

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.startRunning()

            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self = self, let cont = self.continuation else { return }
                self.continuation = nil
                self.session?.stopRunning()
                self.session = nil
                cont.resume(throwing: StraightenUpError.captureTimeout)
            }
        }
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1
        guard frameCount > warmupFrames else { return }
        guard let continuation = self.continuation else { return }

        self.continuation = nil
        session?.stopRunning()
        session = nil

        continuation.resume(returning: sampleBuffer)
    }

    public static func listCameras() -> [CameraInfo] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discoverySession.devices.map { device in
            CameraInfo(
                id: device.uniqueID,
                name: device.localizedName,
                manufacturer: device.manufacturer,
                isActive: !device.isSuspended
            )
        }
    }
}

public enum StraightenUpError: Error, CustomStringConvertible {
    case noCameraFound
    case cameraSetupFailed(String)
    case captureTimeout
    case noPoseDetected
    case insufficientJoints(String)
    case notCalibrated
    case calibrationFailed(String)

    public var description: String {
        switch self {
        case .noCameraFound:
            return "No camera found. Use 'list-cameras' to see available devices."
        case .cameraSetupFailed(let reason):
            return "Camera setup failed: \(reason)"
        case .captureTimeout:
            return "Camera capture timed out after 15 seconds."
        case .noPoseDetected:
            return "No human body pose detected in frame."
        case .insufficientJoints(let detail):
            return "Insufficient joint data for posture analysis: \(detail)"
        case .notCalibrated:
            return "Not calibrated. Run 'calibrate' first to set your baseline posture."
        case .calibrationFailed(let reason):
            return "Calibration failed: \(reason)"
        }
    }
}
