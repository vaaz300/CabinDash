import Testing
@testable import CabinCore

/// Settings > About says which build this is. Every IPA from the "Unsigned IPA" workflow is a beta numbered from its run
/// (run 21 is beta 2.1) until a full release is made; builds from Xcode or the simulator say they are development builds.
@Suite struct AppVersionTests {
    @Test func aBetaShowsItsNumberAndBuild() {
        #expect(AppVersion.describe(channel: "Beta", version: "2.2", build: "22") == "Beta 2.2 (build 22)")
    }

    @Test func aFullReleaseShowsItsNumberAndBuild() {
        #expect(AppVersion.describe(channel: "Release", version: "1.0", build: "35") == "1.0 (build 35)")
    }

    @Test func anythingElseIsADevelopmentBuild() {
        #expect(AppVersion.describe(channel: "Development", version: "0.0", build: "1") == "Development build")
        #expect(AppVersion.describe(channel: nil, version: "1.0", build: "1") == "Development build")
        #expect(AppVersion.describe(channel: "", version: "2.2", build: "22") == "Development build")
    }

    @Test func aMissingBuildNumberIsLeftOut() {
        #expect(AppVersion.describe(channel: "Beta", version: "2.2", build: nil) == "Beta 2.2")
        #expect(AppVersion.describe(channel: "Release", version: "1.0", build: "") == "1.0")
    }
}
