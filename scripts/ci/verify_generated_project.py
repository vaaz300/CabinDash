#!/usr/bin/env python3
"""Checks that the .xcodeproj XcodeGen produced really contains what the app needs.

A project can generate without errors and still be missing a file, the asset catalog or the CabinCore
package, and Xcode only complains later (or not at all). This reads the generated project.pbxproj and
compares it with the files in the repository. It does NOT prove the code compiles; the build step does that.

  verify_generated_project.py                       checks CabinDash.xcodeproj in the repository root
  verify_generated_project.py --json FILE           reads a pbxproj already converted to JSON (used by tests)
"""
import argparse
import json
import pathlib
import plistlib
import subprocess
import sys

import ghactions

ROOT = pathlib.Path(__file__).resolve().parents[2]
TARGET = "CabinDash"
PACKAGE_DIR = "CabinCore"
PACKAGE_PRODUCT = "CabinCore"


class Project:
    """A thin reader over the objects dictionary of a pbxproj (as JSON)."""

    def __init__(self, data: dict):
        self.objects = data["objects"]
        self.parent = {}
        for oid, obj in self.objects.items():
            if obj.get("isa") in ("PBXGroup", "PBXVariantGroup", "XCVersionGroup"):
                for child in obj.get("children", []):
                    self.parent[child] = oid

    def of_type(self, isa):
        return {oid: obj for oid, obj in self.objects.items() if obj.get("isa") == isa}

    def target(self, name):
        for oid, obj in self.of_type("PBXNativeTarget").items():
            if obj.get("name") == name:
                return oid, obj
        return None, None

    def phase(self, target, isa):
        for oid in target.get("buildPhases", []):
            if self.objects[oid].get("isa") == isa:
                return self.objects[oid]
        return None

    def path_of(self, oid):
        """Repository-relative path of a file reference, found by walking up its groups."""
        segments, node = [], oid
        while node:
            obj = self.objects.get(node, {})
            if obj.get("sourceTree") == "SOURCE_ROOT" and obj.get("path"):
                segments.insert(0, obj["path"])
                break
            if obj.get("path"):
                segments.insert(0, obj["path"])
            node = self.parent.get(node)
        return "/".join(segments)

    def phase_paths(self, phase):
        paths = []
        for build_file_id in (phase or {}).get("files", []):
            build_file = self.objects.get(build_file_id, {})
            if "fileRef" in build_file:
                paths.append(self.path_of(build_file["fileRef"]))
        return paths

    def build_settings(self, target):
        configs = self.objects[target["buildConfigurationList"]]["buildConfigurations"]
        return {self.objects[c]["name"]: self.objects[c].get("buildSettings", {}) for c in configs}

    def project_build_settings(self):
        """Project-level settings by configuration name. XcodeGen writes the deployment target here, not on the target."""
        project_obj = next(iter(self.of_type("PBXProject").values()))
        configs = self.objects[project_obj["buildConfigurationList"]]["buildConfigurations"]
        return {self.objects[c]["name"]: self.objects[c].get("buildSettings", {}) for c in configs}

    def effective_settings(self, target):
        """What Xcode would use: project-level settings, overridden by the target's own."""
        project_level = self.project_build_settings()
        merged = {}
        for name, own in self.build_settings(target).items():
            merged[name] = {**project_level.get(name, {}), **own}
        return merged


def check(project: Project, root: pathlib.Path, scheme_exists: bool, plist: dict, expected_schemes: list,
          scheme_detail: str = ""):
    """Returns a list of (description, ok, detail)."""
    results = []

    def record(description, ok, detail=""):
        results.append((description, bool(ok), detail))

    _, target = project.target(TARGET)
    record(f"Target '{TARGET}' exists and is an application",
           target and target.get("productType") == "com.apple.product-type.application")
    if not target:
        return results

    # Source files
    wanted = sorted(p.relative_to(root).as_posix() for p in (root / "CabinDash").rglob("*.swift"))
    in_sources = project.phase_paths(project.phase(target, "PBXSourcesBuildPhase"))
    missing = [p for p in wanted if p not in in_sources]
    if missing and all("/" not in p for p in in_sources):
        # Groups could not be resolved to full paths; fall back to file names.
        names = {pathlib.PurePosixPath(p).name for p in in_sources}
        missing = [p for p in wanted if pathlib.PurePosixPath(p).name not in names]
    record(f"All {len(wanted)} Swift files in CabinDash/ are in the Sources build phase", not missing,
           "missing: " + ", ".join(missing) if missing else "")

    # Resources
    resources = project.phase_paths(project.phase(target, "PBXResourcesBuildPhase"))
    record("Asset catalog is in the Resources build phase",
           any(p.endswith("Assets.xcassets") for p in resources), f"resources: {resources}")
    record("PrivacyInfo.xcprivacy is in the Resources build phase",
           any(p.endswith("PrivacyInfo.xcprivacy") for p in resources), f"resources: {resources}")

    # CabinCore package
    local_refs = project.of_type("XCLocalSwiftPackageReference")
    folder_refs = [o for o in project.of_type("PBXFileReference").values()
                   if o.get("path") == PACKAGE_DIR and o.get("lastKnownFileType") == "folder"]
    record(f"Local package '{PACKAGE_DIR}' is referenced",
           any(o.get("relativePath") == PACKAGE_DIR for o in local_refs.values()) or folder_refs)
    product_ids = [oid for oid, o in project.of_type("XCSwiftPackageProductDependency").items()
                   if o.get("productName") == PACKAGE_PRODUCT]
    record(f"Target depends on the '{PACKAGE_PRODUCT}' product",
           any(pid in target.get("packageProductDependencies", []) for pid in product_ids))
    frameworks = project.phase(target, "PBXFrameworksBuildPhase") or {}
    linked = any(project.objects.get(f, {}).get("productRef") in product_ids for f in frameworks.get("files", []))
    record(f"'{PACKAGE_PRODUCT}' is linked in the Frameworks build phase", linked)

    # Build settings
    settings = project.effective_settings(target)
    for config in ("Debug", "Release"):
        s = settings.get(config, {})
        record(f"{config}: Info.plist is Config/Info.plist", s.get("INFOPLIST_FILE") == "Config/Info.plist",
               f"INFOPLIST_FILE = {s.get('INFOPLIST_FILE')}")
        record(f"{config}: deployment target is iOS 17.0", s.get("IPHONEOS_DEPLOYMENT_TARGET") == "17.0",
               f"IPHONEOS_DEPLOYMENT_TARGET = {s.get('IPHONEOS_DEPLOYMENT_TARGET')}")
        record(f"{config}: iPhone only", str(s.get("TARGETED_DEVICE_FAMILY")) == "1",
               f"TARGETED_DEVICE_FAMILY = {s.get('TARGETED_DEVICE_FAMILY')}")
        record(f"{config}: app icon and accent colour names set",
               s.get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon"
               and s.get("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME") == "AccentColor")
        record(f"{config}: bundle id comes from Signing.xcconfig",
               s.get("PRODUCT_BUNDLE_IDENTIFIER") == "$(CABIN_BUNDLE_ID)",
               f"PRODUCT_BUNDLE_IDENTIFIER = {s.get('PRODUCT_BUNDLE_IDENTIFIER')}")

    # No signing data baked into the generated project
    baked = []
    for obj in project.of_type("XCBuildConfiguration").values():
        team = obj.get("buildSettings", {}).get("DEVELOPMENT_TEAM")
        if team:
            baked.append(team)
    record("No DEVELOPMENT_TEAM is written into the project", not baked, "found: " + ", ".join(baked) if baked else "")

    project_obj = next(iter(project.of_type("PBXProject").values()))
    project_configs = project.objects[project_obj["buildConfigurationList"]]["buildConfigurations"]
    record("Signing.xcconfig is attached to the project configurations",
           all("baseConfigurationReference" in project.objects[c] for c in project_configs))

    record("Scheme 'CabinDash' is available to xcodebuild", scheme_exists, scheme_detail)

    # Generated Info.plist
    record("Info.plist has a location usage description",
           bool(str(plist.get("NSLocationWhenInUseUsageDescription", "")).strip()))
    # Without it, asking for Contacts access makes iOS close the app.
    record("Info.plist has a contacts usage description",
           bool(str(plist.get("NSContactsUsageDescription", "")).strip()))
    record("Info.plist LSApplicationQueriesSchemes matches Catalog.swift",
           list(plist.get("LSApplicationQueriesSchemes", [])) == expected_schemes,
           f"plist has {len(plist.get('LSApplicationQueriesSchemes', []))}, catalog has {len(expected_schemes)}")
    record("Info.plist declares both landscape orientations and no portrait",
           set(plist.get("UISupportedInterfaceOrientations", [])) == {
               "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"})
    record("Info.plist has a SpotifyClientID entry that comes from a build setting",
           plist.get("SpotifyClientID") == "$(SPOTIFY_CLIENT_ID)")
    record("Info.plist has a CabinDashChannel entry that comes from a build setting",
           plist.get("CabinDashChannel") == "$(CABIN_CHANNEL)")
    record("Info.plist has a launch screen colour and a scene manifest",
           "UILaunchScreen" in plist and "UIApplicationSceneManifest" in plist)
    return results


def find_scheme(xcodeproj: pathlib.Path):
    """Returns (found, detail). A shared scheme file is the usual case. If it is not where expected,
    ask xcodebuild itself, because that is what the build step will do: it also lists schemes Xcode makes automatically."""
    files = sorted(p.relative_to(xcodeproj).as_posix() for p in xcodeproj.rglob("*.xcscheme"))
    shared = xcodeproj / "xcshareddata" / "xcschemes" / f"{TARGET}.xcscheme"
    if shared.exists():
        return True, "shared scheme file present"
    listed, problem = [], ""
    try:
        import pick_package_scheme
        result = subprocess.run(["xcodebuild", "-list", "-project", str(xcodeproj), "-json"],
                                capture_output=True, text=True, timeout=180)
        if result.returncode == 0:
            listed = pick_package_scheme.schemes_from(result.stdout)
        else:
            problem = "xcodebuild -list failed: " + result.stderr.strip()[:200]
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        problem = f"could not run xcodebuild -list: {error}"
    found = TARGET in listed
    detail = (f"no shared scheme file; scheme files on disk: {files or 'none'}; "
              f"xcodebuild lists: {listed or 'nothing'}" + (f"; {problem}" if problem else ""))
    return found, detail


def catalog_schemes(root: pathlib.Path):
    sys.path.insert(0, str(root / "scripts"))
    import check_schemes  # noqa: E402  (the repository's own script)
    seen = []
    for entry in check_schemes.catalog_entries():
        if entry["scheme"] and entry["scheme"] not in seen:
            seen.append(entry["scheme"])
    return seen


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("--json", help="pbxproj already converted to JSON")
    args = parser.parse_args(argv)
    root = pathlib.Path(args.root)
    xcodeproj = root / f"{TARGET}.xcodeproj"

    if args.json:
        data = json.loads(pathlib.Path(args.json).read_text())
        scheme_exists, scheme_detail = True, "not checked (--json mode)"
    else:
        pbxproj = xcodeproj / "project.pbxproj"
        if not pbxproj.exists():
            ghactions.error(f"{pbxproj} does not exist; project generation did not produce a project.",
                            title="Generated project")
            return 1
        converted = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(pbxproj)],
                                   capture_output=True, text=True)
        if converted.returncode != 0:
            ghactions.error("plutil could not read project.pbxproj: " + converted.stderr.strip(),
                            title="Generated project")
            return 1
        data = json.loads(converted.stdout)
        scheme_exists, scheme_detail = find_scheme(xcodeproj)

    with (root / "Config" / "Info.plist").open("rb") as handle:
        plist = plistlib.load(handle)

    results = check(Project(data), root, scheme_exists, plist, catalog_schemes(root), scheme_detail)
    failed = [r for r in results if not r[1]]

    lines = ["### Generated Xcode project", "", "| Check | Result |", "|---|---|"]
    for description, ok, detail in results:
        lines.append(f"| {description} | {'ok' if ok else 'FAIL ' + detail} |")
    lines += ["", "This compares the project XcodeGen wrote with the files in the repository. "
              "It does not prove the code compiles."]
    ghactions.summary("\n".join(lines))

    for description, _, detail in failed:
        ghactions.error(f"{description}. {detail}".strip(), title="Generated project")
    if failed:
        return 1
    print(f"Generated project OK ({len(results)} checks).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
