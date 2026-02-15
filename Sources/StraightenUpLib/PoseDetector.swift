import Vision
import CoreImage
import CoreGraphics
import AVFoundation
import AppKit

public struct PoseDetector {
    private static let minimumConfidence: Float = 0.1

    public static func detectPose(from sampleBuffer: CMSampleBuffer) throws -> [String: JointPoint] {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw StraightenUpError.noPoseDetected
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let request = VNDetectHumanBodyPoseRequest()
        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw StraightenUpError.noPoseDetected
        }

        return try extractJoints(from: observation)
    }

    public static func detectPose(from cgImage: CGImage) throws -> [String: JointPoint] {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw StraightenUpError.noPoseDetected
        }

        return try extractJoints(from: observation)
    }

    public struct DiagnosticResult {
        public let imageWidth: Int
        public let imageHeight: Int
        public let poseDetected: Bool
        public let joints: [String: JointPoint]
        public let allJointDetails: [(name: String, x: Double, y: Double, confidence: Double)]
    }

    public static func diagnose(from sampleBuffer: CMSampleBuffer) -> DiagnosticResult {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return DiagnosticResult(imageWidth: 0, imageHeight: 0, poseDetected: false, joints: [:], allJointDetails: [])
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let request = VNDetectHumanBodyPoseRequest()

        do {
            try handler.perform([request])
        } catch {
            return DiagnosticResult(imageWidth: width, imageHeight: height, poseDetected: false, joints: [:], allJointDetails: [])
        }

        guard let observation = request.results?.first else {
            return DiagnosticResult(imageWidth: width, imageHeight: height, poseDetected: false, joints: [:], allJointDetails: [])
        }

        var allDetails: [(name: String, x: Double, y: Double, confidence: Double)] = []
        var joints: [String: JointPoint] = [:]

        let jointNames: [(String, VNHumanBodyPoseObservation.JointName)] = allJointNames()

        for (name, jointName) in jointNames {
            if let point = try? observation.recognizedPoint(jointName) {
                allDetails.append((name: name, x: Double(point.location.x), y: Double(point.location.y), confidence: Double(point.confidence)))
                if point.confidence >= minimumConfidence {
                    joints[name] = JointPoint(
                        x: Double(point.location.x),
                        y: Double(point.location.y),
                        confidence: Double(point.confidence)
                    )
                }
            }
        }

        return DiagnosticResult(imageWidth: width, imageHeight: height, poseDetected: true, joints: joints, allJointDetails: allDetails)
    }

    private static func allJointNames() -> [(String, VNHumanBodyPoseObservation.JointName)] {
        return [
            ("nose", .nose),
            ("neck", .neck),
            ("left_ear", .leftEar),
            ("right_ear", .rightEar),
            ("left_eye", .leftEye),
            ("right_eye", .rightEye),
            ("left_shoulder", .leftShoulder),
            ("right_shoulder", .rightShoulder),
            ("left_elbow", .leftElbow),
            ("right_elbow", .rightElbow),
            ("left_wrist", .leftWrist),
            ("right_wrist", .rightWrist),
            ("left_hip", .leftHip),
            ("right_hip", .rightHip),
            ("root", .root),
        ]
    }

    /// Save CMSampleBuffer as a JPEG image file. Returns the file path on success.
    public static func saveImage(from sampleBuffer: CMSampleBuffer, to url: URL) -> Bool {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return false
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            return false
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return false
        }

        do {
            try jpegData.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func extractJoints(from observation: VNHumanBodyPoseObservation) throws -> [String: JointPoint] {
        var joints: [String: JointPoint] = [:]

        let jointNames: [(String, VNHumanBodyPoseObservation.JointName)] = [
            ("left_ear", .leftEar),
            ("right_ear", .rightEar),
            ("left_shoulder", .leftShoulder),
            ("right_shoulder", .rightShoulder),
            ("left_hip", .leftHip),
            ("right_hip", .rightHip),
            ("neck", .neck),
            ("nose", .nose),
            ("left_elbow", .leftElbow),
            ("right_elbow", .rightElbow),
            ("left_wrist", .leftWrist),
            ("right_wrist", .rightWrist),
            ("root", .root),
        ]

        for (name, jointName) in jointNames {
            if let point = try? observation.recognizedPoint(jointName),
               point.confidence >= minimumConfidence {
                joints[name] = JointPoint(
                    x: Double(point.location.x),
                    y: Double(point.location.y),
                    confidence: Double(point.confidence)
                )
            }
        }

        return joints
    }
}
