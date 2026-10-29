import Foundation

/// Which build this is, as Settings > About says it.
///
/// Every IPA built by the "Unsigned IPA (manual)" workflow is a beta numbered from the workflow's run (run 21 is beta 2.1),
/// until a full release is made by typing its version into the workflow. The workflow writes the channel ("Beta" or
/// "Release"), the version and the build number into the app. Builds from Xcode or the simulator are development builds.
/// See CHANGELOG.md and scripts/ci/app_version.py.
public enum AppVersion {
    public static func describe(channel: String?, version: String?, build: String?) -> String {
        let suffix = build.flatMap { $0.isEmpty ? nil : " (build \($0))" } ?? ""
        let number = version ?? ""
        switch channel {
        case "Beta" where !number.isEmpty:
            return "Beta \(number)\(suffix)"
        case "Release" where !number.isEmpty:
            return "\(number)\(suffix)"
        default:
            return "Development build"
        }
    }
}
