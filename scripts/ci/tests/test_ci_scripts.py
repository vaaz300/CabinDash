"""Tests for the CI helper scripts.  Run:  python3 scripts/ci/tests/test_ci_scripts.py

IMPORTANT: the sample logs and the sample project below are written by hand from what Xcode is known to
print and produce. They were not captured from a real run. They prove the scripts behave correctly on that
input; whether Xcode's real output matches is only confirmed by the first run on GitHub Actions.
"""
import contextlib
import io
import json
import os
import pathlib
import shutil
import struct
import sys
import tempfile
import unittest
import zlib
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
CI = HERE.parent
REPO = CI.parent.parent
sys.path.insert(0, str(CI))
sys.path.insert(0, str(REPO / "scripts"))

import add_spotify_icon  # noqa: E402
import check_repo  # noqa: E402
import check_tests  # noqa: E402
import pick_package_scheme  # noqa: E402
import select_simulator  # noqa: E402
import summarize_xcodebuild  # noqa: E402
import verify_generated_project as verify  # noqa: E402

BUILD_FAILED = """\
Build description signature: abc
SwiftCompile normal arm64 /Users/runner/work/cabin/cabin/CabinDash/Views/RootView.swift (in target 'CabinDash' from project 'CabinDash')
/Users/runner/work/cabin/cabin/CabinDash/Views/RootView.swift:44:15: error: cannot find 'startUpp' in scope
        await model.startUpp(location: location)
              ^~~~~
/Users/runner/work/cabin/cabin/CabinDash/Views/RootView.swift:44:15: note: did you mean 'startUp'?
/Users/runner/work/cabin/cabin/CabinDash/Model/AppModel.swift:10:5: warning: variable 'x' was never used
/Users/runner/work/cabin/cabin/CabinDash/Model/AppModel.swift:10:5: warning: variable 'x' was never used
ld: symbol(s) not found for architecture arm64
error: Signing for "CabinDash" requires a development team.
/Users/runner/work/cabin/cabin/CabinDash/Views/RootView.swift:44:15: error: cannot find 'startUpp' in scope
** BUILD FAILED **
"""

BUILD_OK = """\
CompileSwift normal arm64 /Users/runner/work/cabin/cabin/CabinDash/Views/RootView.swift
/Users/runner/work/cabin/cabin/CabinDash/Views/RootView.swift:7:9: warning: something harmless
** BUILD SUCCEEDED **
"""

TESTS_PASS = """\
Test Suite 'All tests' passed at 2026-01-01 10:00:00.000.
\t Executed 0 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
◇ Test run started.
✔ Test run with 98 tests in 17 suites passed after 0.045 seconds.
"""

TESTS_FAIL = """\
✘ Test oneDegreeOfLatitudeIsAbout111Km() recorded an issue at DriveTests.swift:41:9: Expectation failed: (abs(meters - 111_195) → 12) < 50
✘ Test run with 98 tests in 17 suites failed after 0.05 seconds with 1 issue.
"""

TESTS_ZERO = """\
Test Suite 'All tests' passed at 2026-01-01 10:00:00.000.
\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
"""

XCTEST_FAIL = """\
/Users/runner/work/cabin/cabin/CabinCore/Tests/CabinCoreTests/X.swift:12: error: -[CabinCoreTests.X testY] : XCTAssertEqual failed: ("1") is not equal to ("2")
Test Case '-[CabinCoreTests.X testY]' failed (0.001 seconds).
\t Executed 3 tests, with 1 failure (0 unexpected) in 0.01 (0.02) seconds
"""


class SummarizeTests(unittest.TestCase):
    def test_errors_are_found_and_deduplicated(self):
        errors, warnings, markers = summarize_xcodebuild.parse(BUILD_FAILED)
        messages = [e["msg"] for e in errors]
        self.assertEqual(messages.count("cannot find 'startUpp' in scope"), 1)
        self.assertIn('Signing for "CabinDash" requires a development team.', messages)
        self.assertTrue(any("symbol(s) not found" in m for m in messages))
        self.assertEqual(len(warnings), 1)
        self.assertEqual(markers, ["** BUILD FAILED **"])

    def test_location_and_note_are_attached(self):
        errors, _, _ = summarize_xcodebuild.parse(BUILD_FAILED)
        first = errors[0]
        self.assertEqual(first["line"], 44)
        self.assertEqual(first["col"], 15)
        self.assertIn("did you mean 'startUp'?", first["notes"])
        self.assertTrue(first["file"].endswith("CabinDash/Views/RootView.swift"))

    def test_success_log_has_no_errors(self):
        errors, warnings, markers = summarize_xcodebuild.parse(BUILD_OK)
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 1)
        self.assertEqual(markers, ["** BUILD SUCCEEDED **"])

    def test_swift_testing_and_xctest_failures_are_errors(self):
        errors, _, _ = summarize_xcodebuild.parse(TESTS_FAIL)
        self.assertEqual(len(errors), 1)
        self.assertEqual(errors[0]["line"], 41)
        errors, _, _ = summarize_xcodebuild.parse(XCTEST_FAIL)
        self.assertTrue(any("XCTAssertEqual" in e["msg"] for e in errors))
        self.assertTrue(any(e["msg"].startswith("Test case failed") for e in errors))

    def test_report_is_written_and_exit_code_is_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = pathlib.Path(tmp) / "build.log"
            log.write_text(BUILD_FAILED)
            code = summarize_xcodebuild.main([str(log), "--title", "Build", "--out", tmp])
            self.assertEqual(code, 0)  # the reporter never decides pass/fail
            report = (pathlib.Path(tmp) / "build-errors.txt").read_text()
            self.assertIn("startUpp", report)
            self.assertIn("RootView.swift:44", report)

    def test_missing_log_is_not_a_crash(self):
        self.assertEqual(summarize_xcodebuild.main(["/nonexistent.log", "--title", "Build"]), 0)


class WarningAnnotationTests(unittest.TestCase):
    """Compiler warnings in our own files become GitHub annotations, which can be read without logging in.
    The job summary has them too, but only a signed-in user can open that."""

    WORKSPACE = "/Users/runner/work/CabinDash/CabinDash"

    def run_main(self, text):
        env = {"GITHUB_ACTIONS": "true", "GITHUB_WORKSPACE": self.WORKSPACE, "GITHUB_STEP_SUMMARY": ""}
        with tempfile.TemporaryDirectory() as tmp:
            log = pathlib.Path(tmp) / "build.log"
            log.write_text(text)
            buffer = io.StringIO()
            with mock.patch.dict(os.environ, env), contextlib.redirect_stdout(buffer):
                code = summarize_xcodebuild.main([str(log), "--title", "App build", "--out", tmp])
        return code, [line for line in buffer.getvalue().splitlines() if line.startswith("::")]

    def test_a_warning_in_our_code_is_annotated_with_file_and_line(self):
        log = f"{self.WORKSPACE}/CabinDash/Views/Map/MapScreen.swift:61:9: warning: variable 'a' was never used\n** BUILD SUCCEEDED **\n"
        code, lines = self.run_main(log)
        self.assertEqual(code, 0)
        self.assertIn(
            "::warning file=CabinDash/Views/Map/MapScreen.swift,line=61,col=9,title=App build::variable 'a' was never used",
            lines,
        )

    def test_a_warning_from_outside_the_repository_is_not_annotated(self):
        log = "/Applications/Xcode.app/Contents/Developer/SDK/Foo.swiftinterface:3:1: warning: not ours\n** BUILD SUCCEEDED **\n"
        _, lines = self.run_main(log)
        self.assertEqual([line for line in lines if line.startswith("::warning")], [])

    def test_at_most_ten_warnings_are_annotated(self):
        log = "".join(
            f"{self.WORKSPACE}/CabinDash/Model/AppModel.swift:{n}:5: warning: unused {n}\n" for n in range(1, 16)
        ) + "** BUILD SUCCEEDED **\n"
        _, lines = self.run_main(log)
        self.assertEqual(len([line for line in lines if line.startswith("::warning")]), 10)

    def test_errors_are_still_annotated_and_the_exit_code_is_still_zero(self):
        log = f"{self.WORKSPACE}/CabinDash/Views/RootView.swift:44:15: error: cannot find 'x' in scope\n** BUILD FAILED **\n"
        code, lines = self.run_main(log)
        self.assertEqual(code, 0)
        self.assertEqual(len([line for line in lines if line.startswith("::error")]), 1)


class CheckTestsTests(unittest.TestCase):
    def evaluate(self, log, declared=98, xcresult=None):
        return check_tests.evaluate(declared, check_tests.from_log(log), xcresult)

    def test_passing_run(self):
        ok, message = self.evaluate(TESTS_PASS)
        self.assertTrue(ok, message)

    def test_failing_run(self):
        ok, _ = self.evaluate(TESTS_FAIL)
        self.assertFalse(ok)
        ok, _ = self.evaluate(XCTEST_FAIL, declared=3)
        self.assertFalse(ok)

    def test_zero_tests_is_not_a_pass(self):
        ok, message = self.evaluate(TESTS_ZERO)
        self.assertFalse(ok)
        self.assertIn("No tests were executed", message)

    def test_fewer_tests_than_declared_is_not_a_pass(self):
        ok, message = self.evaluate(TESTS_PASS, declared=120)
        self.assertFalse(ok)
        self.assertIn("98 of the 120", message)

    def test_no_summary_at_all_is_not_a_pass(self):
        ok, _ = self.evaluate("some unrelated output\n")
        self.assertFalse(ok)

    def test_xcresult_totals_can_stand_in_for_the_log(self):
        ok, _ = self.evaluate("no summary line\n", xcresult={"executed": 98, "failed": False})
        self.assertTrue(ok)
        ok, _ = self.evaluate(TESTS_PASS, xcresult={"executed": 98, "failed": True})
        self.assertFalse(ok)

    def test_declared_count_matches_the_real_sources(self):
        count = check_tests.declared_tests(REPO / "CabinCore" / "Tests")
        self.assertGreater(count, 90)


SIMULATORS = {
    "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
            {"udid": "A", "name": "iPhone 16", "isAvailable": True}],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
            {"udid": "B", "name": "iPhone Air", "isAvailable": True},
            {"udid": "C", "name": "iPad (A16)", "isAvailable": True}],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
            {"udid": "D", "name": "iPhone 17 Pro Max", "isAvailable": True},
            {"udid": "E", "name": "iPhone 17", "isAvailable": True},
            {"udid": "F", "name": "iPad Pro 13-inch (M5)", "isAvailable": True}],
        "com.apple.CoreSimulator.SimRuntime.tvOS-26-1": [
            {"udid": "G", "name": "Apple TV", "isAvailable": True}],
    }
}


class SimulatorTests(unittest.TestCase):
    def test_newest_runtime_and_preferred_phone(self):
        udid, name, runtime = select_simulator.pick(SIMULATORS)
        self.assertEqual((udid, name, runtime), ("E", "iPhone 17", "iOS 26.5"))

    def test_unavailable_devices_are_skipped(self):
        data = json.loads(json.dumps(SIMULATORS))
        for device in data["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-26-5"]:
            device["isAvailable"] = False
        self.assertEqual(select_simulator.pick(data)[0], "B")

    def test_no_phone_gives_none(self):
        self.assertIsNone(select_simulator.pick({"devices": {"com.apple.CoreSimulator.SimRuntime.tvOS-26-1": []}}))


def fake_project(root: pathlib.Path):
    """A project.pbxproj (as JSON) shaped like XcodeGen's output, built from the files that really exist."""
    objects = {}
    counter = [0]

    def new(obj):
        counter[0] += 1
        oid = f"ID{counter[0]:04d}"
        objects[oid] = obj
        return oid

    def group_for(directory: pathlib.Path):
        children = []
        for child in sorted(directory.iterdir()):
            if child.name.startswith("."):
                continue
            if child.is_dir() and child.suffix not in (".xcassets",):
                children.append(group_for(child))
            else:
                children.append(new({"isa": "PBXFileReference", "path": child.name, "sourceTree": "<group>"}))
        return new({"isa": "PBXGroup", "path": directory.name, "sourceTree": "<group>", "children": children})

    app_group = group_for(root / "CabinDash")
    main_group = new({"isa": "PBXGroup", "sourceTree": "<group>", "children": [app_group]})

    def by_path(oid_map):
        return {oid: obj for oid, obj in objects.items() if obj["isa"] == "PBXFileReference"}

    files = by_path(objects)

    def path_for(oid):
        parts, node = [], oid
        parents = {c: g for g, o in objects.items() if o["isa"] == "PBXGroup" for c in o.get("children", [])}
        while node:
            if objects[node].get("path"):
                parts.insert(0, objects[node]["path"])
            node = parents.get(node)
        return "/".join(parts)

    swift_ids = [oid for oid in files if objects[oid]["path"].endswith(".swift")]
    resource_ids = [oid for oid in files if objects[oid]["path"] in ("Assets.xcassets", "PrivacyInfo.xcprivacy")]
    # asset catalog folders are recorded as one reference, with their inner files skipped
    asset = new({"isa": "PBXFileReference", "path": "Assets.xcassets", "sourceTree": "<group>"})
    objects[app_group]["children"].append(asset)
    resource_ids = [oid for oid in resource_ids if objects[oid]["path"] == "PrivacyInfo.xcprivacy"] + [asset]

    sources = new({"isa": "PBXSourcesBuildPhase",
                   "files": [new({"isa": "PBXBuildFile", "fileRef": i}) for i in swift_ids]})
    resources = new({"isa": "PBXResourcesBuildPhase",
                     "files": [new({"isa": "PBXBuildFile", "fileRef": i}) for i in resource_ids]})
    product = new({"isa": "XCSwiftPackageProductDependency", "productName": "CabinCore"})
    frameworks = new({"isa": "PBXFrameworksBuildPhase",
                      "files": [new({"isa": "PBXBuildFile", "productRef": product})]})
    package = new({"isa": "XCLocalSwiftPackageReference", "relativePath": "CabinCore"})

    settings = {
        "INFOPLIST_FILE": "Config/Info.plist",
        "TARGETED_DEVICE_FAMILY": "1", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "PRODUCT_BUNDLE_IDENTIFIER": "$(CABIN_BUNDLE_ID)",
    }
    xcconfig = new({"isa": "PBXFileReference", "path": "Config/Signing.xcconfig", "sourceTree": "SOURCE_ROOT"})
    target_configs = [new({"isa": "XCBuildConfiguration", "name": n, "buildSettings": dict(settings)})
                      for n in ("Debug", "Release")]
    # Seen in a real GitHub run: XcodeGen writes options.deploymentTarget on the PROJECT configurations,
    # and leaves it off the target. The first version of this fixture had it on the target, which hid a bug.
    project_configs = [new({"isa": "XCBuildConfiguration", "name": n,
                            "buildSettings": {"IPHONEOS_DEPLOYMENT_TARGET": "17.0"},
                            "baseConfigurationReference": xcconfig}) for n in ("Debug", "Release")]
    target = new({
        "isa": "PBXNativeTarget", "name": "CabinDash", "productType": "com.apple.product-type.application",
        "buildPhases": [sources, frameworks, resources], "packageProductDependencies": [product],
        "buildConfigurationList": new({"isa": "XCConfigurationList", "buildConfigurations": target_configs}),
    })
    new({"isa": "PBXProject", "targets": [target], "packageReferences": [package], "mainGroup": main_group,
         "buildConfigurationList": new({"isa": "XCConfigurationList", "buildConfigurations": project_configs})})
    return {"objects": objects}, {"sources": sources, "product": product, "target": target}


class VerifyProjectTests(unittest.TestCase):
    def run_check(self, data, scheme_exists=True):
        import plistlib
        with (REPO / "Config" / "Info.plist").open("rb") as handle:
            plist = plistlib.load(handle)
        results = verify.check(verify.Project(data), REPO, scheme_exists, plist, verify.catalog_schemes(REPO))
        return [(d, ok, detail) for d, ok, detail in results if not ok]

    def test_a_complete_project_passes(self):
        data, _ = fake_project(REPO)
        self.assertEqual(self.run_check(data), [])

    def test_a_missing_source_file_is_reported(self):
        data, ids = fake_project(REPO)
        sources = data["objects"][ids["sources"]]
        sources["files"] = sources["files"][1:]
        failures = self.run_check(data)
        self.assertEqual(len(failures), 1)
        self.assertIn("Swift files", failures[0][0])

    def test_a_missing_package_link_is_reported(self):
        data, ids = fake_project(REPO)
        data["objects"][ids["target"]]["packageProductDependencies"] = []
        self.assertTrue(any("depends on" in d for d, _, _ in self.run_check(data)))

    def test_a_baked_in_team_id_is_reported(self):
        data, _ = fake_project(REPO)
        for obj in data["objects"].values():
            if obj["isa"] == "XCBuildConfiguration":
                obj["buildSettings"]["DEVELOPMENT_TEAM"] = "ABCDE12345"
                break
        self.assertTrue(any("DEVELOPMENT_TEAM" in d for d, _, _ in self.run_check(data)))

    def test_a_missing_scheme_is_reported(self):
        data, _ = fake_project(REPO)
        self.assertTrue(any("cheme" in d for d, _, _ in self.run_check(data, scheme_exists=False)))

    def project_configs(self, data):
        project = next(o for o in data["objects"].values() if o["isa"] == "PBXProject")
        ids = data["objects"][project["buildConfigurationList"]]["buildConfigurations"]
        return [data["objects"][i] for i in ids]

    def test_deployment_target_is_read_from_the_project_level(self):
        data, _ = fake_project(REPO)
        self.assertTrue(all(c["buildSettings"]["IPHONEOS_DEPLOYMENT_TARGET"] == "17.0"
                            for c in self.project_configs(data)))
        self.assertEqual(self.run_check(data), [])

    def test_a_target_level_value_overrides_the_project_level(self):
        data, ids = fake_project(REPO)
        target = data["objects"][ids["target"]]
        for config_id in data["objects"][target["buildConfigurationList"]]["buildConfigurations"]:
            data["objects"][config_id]["buildSettings"]["IPHONEOS_DEPLOYMENT_TARGET"] = "16.0"
        failures = self.run_check(data)
        self.assertEqual(len(failures), 2)
        self.assertTrue(all("deployment target" in d for d, _, _ in failures))

    def test_a_missing_deployment_target_is_reported(self):
        data, _ = fake_project(REPO)
        for config in self.project_configs(data):
            del config["buildSettings"]["IPHONEOS_DEPLOYMENT_TARGET"]
        failures = self.run_check(data)
        self.assertEqual(len(failures), 2)
        self.assertIn("None", failures[0][2])

    def test_scheme_lookup_accepts_a_shared_file(self):
        with tempfile.TemporaryDirectory() as folder:
            project = pathlib.Path(folder) / "CabinDash.xcodeproj"
            schemes = project / "xcshareddata" / "xcschemes"
            schemes.mkdir(parents=True)
            (schemes / "CabinDash.xcscheme").write_text("<Scheme/>")
            found, detail = verify.find_scheme(project)
        self.assertTrue(found)
        self.assertIn("shared", detail)


# Built in pieces so this file does not itself contain a PEM header that the repository scan would flag.
FAKE_KEY = "-----BEGIN " + "PRIVATE KEY-----\n" + "A" * 64 + "\n-----END " + "PRIVATE KEY-----\n"


class RepoLayoutTests(unittest.TestCase):
    def copy_repo(self):
        tmp = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        target = tmp / "repo"
        shutil.copytree(REPO, target, ignore=shutil.ignore_patterns(".git", "__pycache__", "*.xcodeproj"))
        return target

    def test_the_real_repository_passes(self):
        self.assertEqual(check_repo.main(REPO), 0)

    def test_a_nested_upload_is_explained(self):
        repo = self.copy_repo()
        wrapper = repo.parent / "wrapper"
        wrapper.mkdir()
        shutil.move(str(repo), str(wrapper / "CabinDash-iOS"))
        self.assertEqual(check_repo.main(wrapper), 1)

    def test_signing_material_is_refused(self):
        repo = self.copy_repo()
        (repo / "AuthKey_ABC123.p8").write_text(FAKE_KEY)
        self.assertEqual(check_repo.main(repo), 1)

    def test_a_pasted_key_in_a_text_file_is_refused(self):
        repo = self.copy_repo()
        (repo / "notes.md").write_text("my key:\n" + FAKE_KEY)
        self.assertEqual(check_repo.main(repo), 1)

    def test_team_id_in_project_yml_is_refused(self):
        repo = self.copy_repo()
        with (repo / "project.yml").open("a") as handle:
            handle.write("\n    DEVELOPMENT_TEAM: ABCDE12345\n")
        self.assertEqual(check_repo.main(repo), 1)


ICON = "CabinDash/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def png_bytes(width, height, color_type, extra_chunks=()):
    """A valid 8-bit PNG of one flat colour. color_type 2 is RGB, 6 is RGBA."""
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color_type]
    raw = (b"\x00" + b"\x10" * (width * channels)) * height
    header = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    extras = b"".join(chunk(kind, data) for kind, data in extra_chunks)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + extras + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


class AppIconTests(unittest.TestCase):
    """iOS refuses an app icon that is not 1024 x 1024 or that has transparency. Catch that before an upload does."""

    copy_repo = RepoLayoutTests.copy_repo

    def with_icon(self, data):
        repo = self.copy_repo()
        (repo / ICON).write_bytes(data)
        return repo

    def test_a_plain_1024_rgb_icon_passes(self):
        self.assertEqual(check_repo.main(self.with_icon(png_bytes(1024, 1024, 2))), 0)

    def test_an_icon_with_an_alpha_channel_is_refused(self):
        self.assertEqual(check_repo.main(self.with_icon(png_bytes(1024, 1024, 6))), 1)

    def test_an_icon_with_a_transparency_chunk_is_refused(self):
        self.assertEqual(check_repo.main(self.with_icon(png_bytes(1024, 1024, 2, [(b"tRNS", b"\x00\x00\x00\x00\x00\x00")]))), 1)

    def test_an_icon_of_the_wrong_size_is_refused(self):
        self.assertEqual(check_repo.main(self.with_icon(png_bytes(512, 512, 2))), 1)

    def test_a_file_that_is_not_a_png_is_refused(self):
        self.assertEqual(check_repo.main(self.with_icon(b"not a png at all")), 1)


class AddSpotifyIconTests(unittest.TestCase):
    """scripts/add_spotify_icon.py puts the icon from Spotify's guidelines page into the asset catalogue."""

    def setUp(self):
        self.temp = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.root = self.temp / "repo"
        self.root.mkdir()

    def source(self, data):
        path = self.temp / "icon.png"
        path.write_bytes(data)
        return path

    def imageset(self):
        return self.root / "CabinDash" / "Assets.xcassets" / "SpotifyIcon.imageset"

    def test_installs_a_png_and_writes_contents(self):
        data = png_bytes(64, 64, 6)
        with contextlib.redirect_stdout(io.StringIO()):
            code = add_spotify_icon.install(self.source(data), self.root)
        self.assertEqual(code, 0)
        self.assertEqual((self.imageset() / "SpotifyIcon.png").read_bytes(), data)
        contents = json.loads((self.imageset() / "Contents.json").read_text())
        self.assertEqual([image["filename"] for image in contents["images"]], ["SpotifyIcon.png"])

    def test_rejects_a_non_png_file(self):
        with contextlib.redirect_stderr(io.StringIO()):
            code = add_spotify_icon.install(self.source(b"definitely not a png"), self.root)
        self.assertEqual(code, 1)
        self.assertFalse(self.imageset().exists())

    def test_rejects_a_missing_file(self):
        with contextlib.redirect_stderr(io.StringIO()):
            code = add_spotify_icon.install(self.temp / "nothing-here.png", self.root)
        self.assertEqual(code, 1)
        self.assertFalse(self.imageset().exists())

    def test_rejects_a_png_smaller_than_21_pixels(self):
        with contextlib.redirect_stderr(io.StringIO()):
            code = add_spotify_icon.install(self.source(png_bytes(20, 20, 6)), self.root)
        self.assertEqual(code, 1)
        self.assertFalse(self.imageset().exists())

    def test_rejects_a_png_that_is_not_square(self):
        with contextlib.redirect_stderr(io.StringIO()):
            code = add_spotify_icon.install(self.source(png_bytes(64, 32, 6)), self.root)
        self.assertEqual(code, 1)
        self.assertFalse(self.imageset().exists())

    def test_installing_again_replaces_the_icon(self):
        with contextlib.redirect_stdout(io.StringIO()):
            add_spotify_icon.install(self.source(png_bytes(64, 64, 6)), self.root)
            newer = png_bytes(128, 128, 6)
            code = add_spotify_icon.install(self.source(newer), self.root)
        self.assertEqual(code, 0)
        self.assertEqual((self.imageset() / "SpotifyIcon.png").read_bytes(), newer)

    def test_accepts_spotifys_own_files_which_are_one_pixel_off_square(self):
        # Spotify's 2024 icon PNGs are 939 x 940 px. They are used exactly as supplied.
        data = png_bytes(939, 940, 6)
        with contextlib.redirect_stdout(io.StringIO()):
            code = add_spotify_icon.install(self.source(data), self.root)
        self.assertEqual(code, 0)
        self.assertEqual((self.imageset() / "SpotifyIcon.png").read_bytes(), data)

    def test_installs_under_another_asset_name(self):
        data = png_bytes(135, 135, 6)
        with contextlib.redirect_stdout(io.StringIO()):
            code = add_spotify_icon.install(self.source(data), self.root, name="SpotifyLiked")
        self.assertEqual(code, 0)
        imageset = self.root / "CabinDash" / "Assets.xcassets" / "SpotifyLiked.imageset"
        self.assertEqual((imageset / "SpotifyLiked.png").read_bytes(), data)
        contents = json.loads((imageset / "Contents.json").read_text())
        self.assertEqual([image["filename"] for image in contents["images"]], ["SpotifyLiked.png"])

    def test_rejects_an_asset_name_that_is_not_one_of_spotifys(self):
        with contextlib.redirect_stderr(io.StringIO()):
            code = add_spotify_icon.install(self.source(png_bytes(64, 64, 6)), self.root, name="../AppIcon")
        self.assertEqual(code, 1)


class PackageSchemeTests(unittest.TestCase):
    def test_single_library_package(self):
        text = 'Resolve Package Graph\n{"workspace":{"name":"CabinCore","schemes":["CabinCore"]}}'
        self.assertEqual(pick_package_scheme.choose(pick_package_scheme.schemes_from(text)), "CabinCore")

    def test_prefers_the_package_scheme_when_both_exist(self):
        text = '{"workspace":{"name":"CabinCore","schemes":["CabinCore","CabinCore-Package"]}}'
        self.assertEqual(pick_package_scheme.choose(pick_package_scheme.schemes_from(text)), "CabinCore-Package")

    def test_no_json_gives_nothing(self):
        self.assertEqual(pick_package_scheme.choose(pick_package_scheme.schemes_from("no json here")), "")


class WorkflowReferenceTests(unittest.TestCase):
    """Cheap guard for future edits: a workflow must not call a script or action that does not exist."""

    def test_scripts_named_in_workflows_exist(self):
        import re
        folder = REPO / ".github" / "workflows"
        files = sorted(folder.glob("*.yml"))
        self.assertTrue(files, "no workflow files found")
        for path in files:
            text = path.read_text().replace("\\\n", " ")
            for match in re.finditer(r"(?:python3|bash)\s+(?:\.\./)?(scripts/[\w./-]+)", text):
                self.assertTrue((REPO / match.group(1)).exists(), f"{path.name} calls missing {match.group(1)}")
            for match in re.finditer(r"uses:\s+\./(\S+)", text):
                self.assertTrue((REPO / match.group(1) / "action.yml").exists(), f"{path.name} uses missing {match.group(1)}")


if __name__ == "__main__":
    os.environ.pop("GITHUB_ACTIONS", None)
    unittest.main(verbosity=2)
