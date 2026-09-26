import Foundation

/// An inspectable report projection only. It has no reader, model-client,
/// persistence, companion, or setting-changing operation.
struct GGUFCalibrationReportPreview: Sendable {
    enum Status: String, Decodable, Sendable {
        case limitedPass = "limited-shadow-pass"
        case failed = "qualification-failed"

        var title: String { self == .failed ? "Qualification failed" : "Limited shadow pass" }
    }

    static let maximumBytes = 128 * 1024
    let filename: String
    let contentDigest: String
    let modelName: String
    let status: Status
    let measurementScope: String
    let fitCount: Int
    let calibrationCount: Int
    let holdoutCount: Int
    let holdoutCorrect: Int
    let holdoutAccuracy: Double
    let minimumSignedMargin: Double?
    let minimumObservedHoldoutMargin: Double?
    let limitations: [String]

    static func load(from url: URL) throws -> Self {
        guard url.isFileURL else { throw PreviewError.invalid }
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              let size = properties.fileSize, size > 0, size <= maximumBytes else { throw PreviewError.invalid }
        let bytes = try Data(contentsOf: url)
        guard !bytes.isEmpty, bytes.count <= maximumBytes,
              GGUFReaderArtifact.hasUniqueKeys(bytes, maximumDepth: 16),
              let report = try? JSONDecoder().decode(Report.self, from: bytes),
              report.schema == "archi-gguf-reader-calibration/v1",
              report.tokenRule == "prompt-last", report.prefillOnly != false,
              report.measurementScope == GGUFReaderArtifact.promptFinalMeasurementScope,
              (1...24).contains(report.fitCount), (1...24).contains(report.calibrationCount),
              (1...24).contains(report.holdoutCount),
              report.fitCount + report.calibrationCount + report.holdoutCount <= 24,
              (0...report.holdoutCount).contains(report.holdoutCorrect),
              report.holdoutAccuracy.isFinite, (0...1).contains(report.holdoutAccuracy),
              abs(report.holdoutAccuracy - Double(report.holdoutCorrect) / Double(report.holdoutCount)) <= 1e-9,
              validLabel(report.plan.modelName, maximum: 160),
              report.minimumSignedMargin.map({ $0.isFinite && (0...1e6).contains($0) }) ?? true,
              (report.limitations?.count ?? 0) <= 16,
              report.limitations?.allSatisfy({ validLabel($0, maximum: 2_000) }) ?? true else {
            throw PreviewError.invalid
        }
        if report.status == .limitedPass {
            guard report.holdoutCount >= 8, report.holdoutCorrect == report.holdoutCount else {
                throw PreviewError.invalid
            }
        }
        var minimumObserved: Double?
        if let results = report.results {
            guard results.count <= 24,
                  results.allSatisfy({ ["fit", "calibration", "holdout"].contains($0.split)
                      && $0.signedMargin.isFinite && abs($0.signedMargin) <= 1e12 }) else {
                throw PreviewError.invalid
            }
            let heldout = results.filter { $0.split == "holdout" }
            guard heldout.count == report.holdoutCount,
                  heldout.filter({ $0.signedMargin > 0 }).count == report.holdoutCorrect else {
                throw PreviewError.invalid
            }
            if report.status == .limitedPass, let requiredMargin = report.minimumSignedMargin {
                guard results.filter({ $0.split != "fit" }).allSatisfy({ $0.signedMargin >= requiredMargin }) else {
                    throw PreviewError.invalid
                }
            }
            minimumObserved = heldout.map(\.signedMargin).min()
        }
        return Self(filename: url.lastPathComponent, contentDigest: GGUFReaderArtifact.digest(bytes),
            modelName: report.plan.modelName, status: report.status, measurementScope: report.measurementScope,
            fitCount: report.fitCount, calibrationCount: report.calibrationCount,
            holdoutCount: report.holdoutCount, holdoutCorrect: report.holdoutCorrect,
            holdoutAccuracy: report.holdoutAccuracy, minimumSignedMargin: report.minimumSignedMargin,
            minimumObservedHoldoutMargin: minimumObserved, limitations: report.limitations ?? [])
    }

    private static func validLabel(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximum
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private struct Report: Decodable {
        struct Plan: Decodable { let modelName: String }
        struct Result: Decodable { let split: String; let signedMargin: Double }
        let schema: String
        let status: Status
        let measurementScope: String
        let tokenRule: String
        let prefillOnly: Bool?
        let fitCount: Int
        let calibrationCount: Int
        let holdoutCount: Int
        let holdoutCorrect: Int
        let holdoutAccuracy: Double
        let plan: Plan
        let minimumSignedMargin: Double?
        let limitations: [String]?
        let results: [Result]?
    }

    enum PreviewError: Error, LocalizedError {
        case invalid
        var errorDescription: String? {
            "Choose a regular calibration report JSON file no larger than 128 KiB with the supported prompt-final scope and consistent counts, accuracy, and status."
        }
    }
}
