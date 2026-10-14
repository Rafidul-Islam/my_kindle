#!/usr/bin/env python3
"""Generates Inkwell.xcodeproj from the Sources/ and Tests/ directories.

Run this after adding or removing a source file:

    python3 tools/genproj.py

The output is a classic (objectVersion 56) pbxproj, which opens in every recent
Xcode and is also parseable by fastlane, CocoaPods and CI tooling.
"""

from __future__ import annotations

import hashlib
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = "Inkwell"
TEST_TARGET = "InkwellTests"
BUNDLE_ID = "com.rafid.inkwell"
DEPLOYMENT_TARGET = "18.0"
XCODE_VERSION = "1600"

PROJECT_DIR = ROOT / f"{PROJECT_NAME}.xcodeproj"
SOURCES_ROOT = ROOT / "Sources"
TESTS_ROOT = ROOT / "Tests"

FILE_TYPES = {
    ".swift": ("sourcecode.swift", True),
    ".plist": ("text.plist.xml", False),
    ".xcassets": ("folder.assetcatalog", "resources"),
    ".json": ("text.json", "resources"),
    ".md": ("net.daringfireball.markdown", False),
    ".entitlements": ("text.plist.entitlements", False),
}


def uuid_for(key: str) -> str:
    """Deterministic 24-character hex identifier."""
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def file_type_for(path: Path):
    suffix = path.suffix.lower()
    return FILE_TYPES.get(suffix, ("text", False))


def quote(value: str) -> str:
    if value and all(c.isalnum() or c in "_./" for c in value):
        return value
    return '"{}"'.format(value.replace('"', '\\"'))


def walk(root: Path, prefix: str):
    """Yields (relative_path, path) for every file under root, sorted.

    Files inside an `.xcassets` bundle are skipped: the bundle is copied as a
    whole and its contents must never become individual build resources.
    """
    if not root.exists():
        return []
    entries = sorted(root.rglob("*"))
    results = []
    for path in entries:
        is_bundle = path.name.endswith(".xcassets")
        if not path.is_file() and not is_bundle:
            continue
        if any(part.endswith(".xcassets") for part in path.parts[:-1]):
            continue
        results.append((str(path.relative_to(ROOT)), path))
    return results


def group_paths(files):
    """Builds the set of intermediate directory paths under each root."""
    groups = set()
    for rel, _ in files:
        parts = rel.split(os.sep)
        for i in range(1, len(parts)):
            groups.add(tuple(parts[:i]))
    return groups


class Project:
    def __init__(self) -> None:
        self.lines: list[str] = []
        self.file_refs: dict[str, str] = {}       # relative path -> uuid
        self.build_files: dict[str, str] = {}     # relative path -> uuid
        self.source_files: list[str] = []
        self.resource_files: list[str] = []
        self.plist_files: list[str] = []
        self.other_files: list[str] = []

    def emit(self, text: str = "") -> None:
        self.lines.append(text)

    # -- collection -------------------------------------------------------

    def add_files(self, files) -> None:
        for rel, _ in files:
            if rel in self.file_refs:
                continue
            key = f"ref::{rel}"
            self.file_refs[rel] = uuid_for(key)
            kind = file_type_for(Path(rel))[1]
            if kind is True:
                self.source_files.append(rel)
                self.build_files[rel] = uuid_for(f"build::{rel}")
            elif kind == "resources":
                self.resource_files.append(rel)
                self.build_files[rel] = uuid_for(f"build::{rel}")
            elif Path(rel).name == "Info.plist":
                self.plist_files.append(rel)
            else:
                self.other_files.append(rel)


def generate() -> str:
    project = Project()
    source_files = walk(SOURCES_ROOT, "Sources")
    test_files = walk(TESTS_ROOT, "Tests")

    project.add_files(source_files)
    project.add_files(test_files)

    app_target = uuid_for("target::app")
    test_target = uuid_for("target::tests")
    project_object = uuid_for("object::project")
    main_group = uuid_for("group::main")
    products_group = uuid_for("group::products")
    app_product = uuid_for("product::app")
    test_product = uuid_for("product::tests")

    sources_group = uuid_for("group::Sources")
    tests_group = uuid_for("group::Tests")
    resources_group = uuid_for("group::Resources")

    app_sources_phase = uuid_for("phase::app::sources")
    app_frameworks_phase = uuid_for("phase::app::frameworks")
    app_resources_phase = uuid_for("phase::app::resources")
    test_sources_phase = uuid_for("phase::test::sources")
    test_frameworks_phase = uuid_for("phase::test::frameworks")
    test_resources_phase = uuid_for("phase::test::resources")

    project_config_list = uuid_for("configlist::project")
    app_config_list = uuid_for("configlist::app")
    test_config_list = uuid_for("configlist::tests")

    project_debug = uuid_for("config::project::debug")
    project_release = uuid_for("config::project::release")
    app_debug = uuid_for("config::app::debug")
    app_release = uuid_for("config::app::release")
    test_debug = uuid_for("config::tests::debug")
    test_release = uuid_for("config::tests::release")

    proxy = uuid_for("proxy::tests->app")
    dependency = uuid_for("dependency::tests->app")

    out = Project()
    out.emit("// !$*UTF8*$!")
    out.emit("{")
    out.emit("\tarchiveVersion = 1;")
    out.emit("\tclasses = {")
    out.emit("\t};")
    out.emit("\tobjectVersion = 56;")
    out.emit("\tobjects = {")
    out.emit()

    # ---------------- PBXBuildFile ----------------
    out.emit("/* Begin PBXBuildFile section */")
    for rel in project.source_files + project.resource_files:
        out.emit(
            f'\t\t{project.build_files[rel]} /* {Path(rel).name} in Build Phase */ = {{isa = PBXBuildFile; fileRef = {project.file_refs[rel]} /* {Path(rel).name} */; }};'
        )
    out.emit("/* End PBXBuildFile section */")
    out.emit()

    # ---------------- PBXContainerItemProxy ----------------
    out.emit("/* Begin PBXContainerItemProxy section */")
    out.emit(f"\t\t{proxy} /* PBXContainerItemProxy */ = {{")
    out.emit("\t\t\tisa = PBXContainerItemProxy;")
    out.emit(f"\t\t\tcontainerPortal = {project_object} /* Project object */;")
    out.emit("\t\t\tproxyType = 1;")
    out.emit(f"\t\t\tremoteGlobalIDString = {app_target};")
    out.emit(f"\t\t\tremoteInfo = {PROJECT_NAME};")
    out.emit("\t\t};")
    out.emit("/* End PBXContainerItemProxy section */")
    out.emit()

    # ---------------- PBXFileReference ----------------
    out.emit("/* Begin PBXFileReference section */")
    out.emit(f'\t\t{app_product} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
    out.emit(f'\t\t{test_product} /* {TEST_TARGET}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TEST_TARGET}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
    for rel, uuid in sorted(project.file_refs.items(), key=lambda item: item[0]):
        name = Path(rel).name
        ftype, _ = file_type_for(Path(rel))
        explicit = "explicitFileType" if ftype != "folder.assetcatalog" else "lastKnownFileType"
        out.emit(
            f'\t\t{uuid} /* {name} */ = {{isa = PBXFileReference; {explicit} = {ftype}; path = {quote(name)}; sourceTree = "<group>"; }};'
        )
    out.emit("/* End PBXFileReference section */")
    out.emit()

    # ---------------- PBXFrameworksBuildPhase ----------------
    for phase, name in (
        (app_frameworks_phase, PROJECT_NAME),
        (test_frameworks_phase, TEST_TARGET),
    ):
        out.emit("/* Begin PBXFrameworksBuildPhase section */")
        out.emit(f"\t\t{phase} /* Frameworks */ = {{")
        out.emit("\t\t\tisa = PBXFrameworksBuildPhase;")
        out.emit("\t\t\tbuildActionMask = 2147483647;")
        out.emit("\t\t\tfiles = (")
        out.emit("\t\t\t);")
        out.emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out.emit("\t\t};")
        out.emit("/* End PBXFrameworksBuildPhase section */")
        out.emit()

    # ---------------- PBXGroup ----------------
    all_groups: dict[tuple[str, ...], str] = {
        ("Sources",): sources_group,
        ("Tests",): tests_group,
    }

    def group_uuid(path_tuple) -> str:
        if path_tuple not in all_groups:
            all_groups[path_tuple] = uuid_for("group::" + "/".join(path_tuple))
        return all_groups[path_tuple]

    for rel in project.file_refs:
        parts = tuple(Path(rel).parts[:-1])
        for i in range(len(parts)):
            group_uuid(parts[: i + 1])

    group_children: dict[str, list[tuple[str, str, str]]] = {}

    def add_child(parent: str, uuid: str, name: str, path: str) -> None:
        group_children.setdefault(parent, []).append((uuid, name, path))

    for tuple_path, gid in sorted(all_groups.items(), key=lambda item: item[1]):
        if len(tuple_path) == 1:
            continue
        parent = group_uuid(tuple_path[:-1])
        add_child(parent, gid, tuple_path[-1], tuple_path[-1])

    for rel, uuid in sorted(project.file_refs.items(), key=lambda item: item[0]):
        parts = tuple(Path(rel).parts[:-1])
        parent = group_uuid(parts) if parts else main_group
        add_child(parent, uuid, Path(rel).name, Path(rel).name)

    def render_group(gid: str, name: str, path: str, children_source: str) -> None:
        out.emit("/* Begin PBXGroup section */")
        out.emit(f"\t\t{gid} /* {name} */ = {{")
        out.emit("\t\t\tisa = PBXGroup;")
        out.emit("\t\t\tchildren = (")
        for cuid, cname, cpath in sorted(group_children.get(gid, []), key=lambda item: (item[2] != name, item[1])):
            out.emit(f"\t\t\t\t{cuid} /* {cname} */,")
        out.emit("\t\t\t);")
        if path is not None:
            out.emit(f"\t\t\tpath = {quote(path)};")
        else:
            out.emit("\t\t\tname = {};")
        out.emit('\t\t\tsourceTree = "<group>";')
        out.emit("\t\t};")
        out.emit("/* End PBXGroup section */")
        out.emit()

    render_group(sources_group, "Sources", "Sources", "")
    render_group(tests_group, "Tests", "Tests", "")
    for tuple_path, gid in sorted(all_groups.items(), key=lambda item: len(item[0])):
        if len(tuple_path) == 1:
            continue
        render_group(gid, tuple_path[-1], tuple_path[-1], "")
    render_group(products_group, "Products", None, "")

    out.emit("/* Begin PBXGroup section */")
    out.emit(f"\t\t{main_group} = {{")
    out.emit("\t\t\tisa = PBXGroup;")
    out.emit("\t\t\tchildren = (")
    out.emit(f"\t\t\t\t{sources_group} /* Sources */,")
    out.emit(f"\t\t\t\t{tests_group} /* Tests */,")
    out.emit(f"\t\t\t\t{products_group} /* Products */,")
    out.emit("\t\t\t);")
    out.emit("\t\t\tsourceTree = \"<group>\";")
    out.emit("\t\t};")
    out.emit("/* End PBXGroup section */")
    out.emit()

    # ---------------- PBXNativeTarget ----------------
    out.emit("/* Begin PBXNativeTarget section */")
    out.emit(f"\t\t{app_target} /* {PROJECT_NAME} */ = {{")
    out.emit("\t\t\tisa = PBXNativeTarget;")
    out.emit(f"\t\t\tbuildConfigurationList = {app_config_list};")
    out.emit("\t\t\tbuildPhases = (")
    out.emit(f"\t\t\t\t{app_sources_phase} /* Sources */,")
    out.emit(f"\t\t\t\t{app_frameworks_phase} /* Frameworks */,")
    out.emit(f"\t\t\t\t{app_resources_phase} /* Resources */,")
    out.emit("\t\t\t);")
    out.emit("\t\t\tbuildRules = (")
    out.emit("\t\t\t);")
    out.emit("\t\t\tdependencies = (")
    out.emit("\t\t\t);")
    out.emit(f"\t\t\tname = {PROJECT_NAME};")
    out.emit(f"\t\t\tproductName = {PROJECT_NAME};")
    out.emit(f"\t\t\tproductReference = {app_product} /* {PROJECT_NAME}.app */;")
    out.emit('\t\t\tproductType = "com.apple.product-type.application";')
    out.emit("\t\t};")
    out.emit(f"\t\t{test_target} /* {TEST_TARGET} */ = {{")
    out.emit("\t\t\tisa = PBXNativeTarget;")
    out.emit(f"\t\t\tbuildConfigurationList = {test_config_list};")
    out.emit("\t\t\tbuildPhases = (")
    out.emit(f"\t\t\t\t{test_sources_phase} /* Sources */,")
    out.emit(f"\t\t\t\t{test_frameworks_phase} /* Frameworks */,")
    out.emit(f"\t\t\t\t{test_resources_phase} /* Resources */,")
    out.emit("\t\t\t);")
    out.emit("\t\t\tbuildRules = (")
    out.emit("\t\t\t);")
    out.emit("\t\t\tdependencies = (")
    out.emit(f"\t\t\t\t{dependency} /* PBXTargetDependency */,")
    out.emit("\t\t\t);")
    out.emit(f"\t\t\tname = {TEST_TARGET};")
    out.emit(f"\t\t\tproductName = {TEST_TARGET};")
    out.emit(f"\t\t\tproductReference = {test_product} /* {TEST_TARGET}.xctest */;")
    out.emit('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
    out.emit("\t\t};")
    out.emit("/* End PBXNativeTarget section */")
    out.emit()

    # ---------------- PBXProject ----------------
    out.emit("/* Begin PBXProject section */")
    out.emit(f"\t\t{project_object} /* Project object */ = {{")
    out.emit("\t\t\tisa = PBXProject;")
    out.emit("\t\t\tattributes = {")
    out.emit("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    out.emit(f"\t\t\t\tLastSwiftUpdateCheck = {XCODE_VERSION};")
    out.emit(f"\t\t\t\tLastUpgradeCheck = {XCODE_VERSION};")
    out.emit("\t\t\t\tTargetAttributes = {")
    out.emit(f"\t\t\t\t\t{app_target} = {{")
    out.emit("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    out.emit("\t\t\t\t\t};")
    out.emit(f"\t\t\t\t\t{test_target} = {{")
    out.emit("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    out.emit(f"\t\t\t\t\t\tTestTargetID = {app_target};")
    out.emit("\t\t\t\t\t};")
    out.emit("\t\t\t\t};")
    out.emit("\t\t\t};")
    out.emit(f"\t\t\tbuildConfigurationList = {project_config_list};")
    out.emit('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    out.emit("\t\t\tdevelopmentRegion = en;")
    out.emit("\t\t\thasScannedForEncodings = 0;")
    out.emit("\t\t\tknownRegions = (")
    out.emit("\t\t\t\ten,")
    out.emit("\t\t\t\tBase,")
    out.emit("\t\t\t);")
    out.emit(f"\t\t\tmainGroup = {main_group};")
    out.emit(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    out.emit('\t\t\tprojectDirPath = "";')
    out.emit('\t\t\tprojectRoot = "";')
    out.emit("\t\t\ttargets = (")
    out.emit(f"\t\t\t\t{app_target} /* {PROJECT_NAME} */,")
    out.emit(f"\t\t\t\t{test_target} /* {TEST_TARGET} */,")
    out.emit("\t\t\t);")
    out.emit("\t\t};")
    out.emit("/* End PBXProject section */")
    out.emit()

    # ---------------- PBXResourcesBuildPhase ----------------
    def render_resources_phase(uuid: str, files: list[str], label: str) -> None:
        out.emit("/* Begin PBXResourcesBuildPhase section */")
        out.emit(f"\t\t{uuid} /* Resources */ = {{")
        out.emit("\t\t\tisa = PBXResourcesBuildPhase;")
        out.emit("\t\t\tbuildActionMask = 2147483647;")
        out.emit("\t\t\tfiles = (")
        for rel in files:
            out.emit(f"\t\t\t\t{project.build_files[rel]} /* {Path(rel).name} in Resources */,")
        out.emit("\t\t\t);")
        out.emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out.emit("\t\t};")
        out.emit("/* End PBXResourcesBuildPhase section */")
        out.emit()

    render_resources_phase(app_resources_phase, project.resource_files, "app")
    render_resources_phase(test_resources_phase, [], "tests")

    # ---------------- PBXSourcesBuildPhase ----------------
    def render_sources_phase(uuid: str, files: list[str]) -> None:
        out.emit("/* Begin PBXSourcesBuildPhase section */")
        out.emit(f"\t\t{uuid} /* Sources */ = {{")
        out.emit("\t\t\tisa = PBXSourcesBuildPhase;")
        out.emit("\t\t\tbuildActionMask = 2147483647;")
        out.emit("\t\t\tfiles = (")
        for rel in files:
            out.emit(f"\t\t\t\t{project.build_files[rel]} /* {Path(rel).name} in Sources */,")
        out.emit("\t\t\t);")
        out.emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out.emit("\t\t};")
        out.emit("/* End PBXSourcesBuildPhase section */")
        out.emit()

    app_sources = [rel for rel in project.source_files if rel.startswith("Sources")]
    test_sources = [rel for rel in project.source_files if rel.startswith("Tests")]
    render_sources_phase(app_sources_phase, app_sources)
    render_sources_phase(test_sources_phase, test_sources)

    # ---------------- PBXTargetDependency ----------------
    out.emit("/* Begin PBXTargetDependency section */")
    out.emit(f"\t\t{dependency} /* PBXTargetDependency */ = {{")
    out.emit("\t\t\tisa = PBXTargetDependency;")
    out.emit(f"\t\t\ttarget = {app_target} /* {PROJECT_NAME} */;")
    out.emit(f"\t\t\ttargetProxy = {proxy} /* PBXContainerItemProxy */;")
    out.emit("\t\t};")
    out.emit("/* End PBXTargetDependency section */")
    out.emit()

    # ---------------- XCBuildConfiguration ----------------
    shared_project = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "SDKROOT": "iphoneos",
        "SWIFT_STRICT_CONCURRENCY": "minimal",
        "SWIFT_VERSION": "5.0",
    }
    debug_project = dict(shared_project)
    debug_project.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": '"DEBUG=1 $(inherited)"',
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    })
    release_project = dict(shared_project)
    release_project.update({
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
        "VALIDATE_PRODUCT": "YES",
    })

    info_plist_rel = "Sources/Resources/Info.plist"

    shared_app = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": info_plist_rel,
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SUPPORTS_MACCATALYST": "NO",
        "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    app_debug_settings = dict(shared_app)
    app_release_settings = dict(shared_app)

    shared_tests = {
        "BUNDLE_LOADER": '"$(TEST_HOST)"',
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.tests",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "TARGETED_DEVICE_FAMILY": "1",
        "TEST_HOST": f'"$(BUILT_PRODUCTS_DIR)/{PROJECT_NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{PROJECT_NAME}"',
    }
    tests_debug_settings = dict(shared_tests)
    tests_release_settings = dict(shared_tests)

    def render_config(uuid: str, name: str, settings: dict[str, str]) -> None:
        out.emit("/* Begin XCBuildConfiguration section */")
        out.emit(f"\t\t{uuid} /* {name} */ = {{")
        out.emit("\t\t\tisa = XCBuildConfiguration;")
        out.emit("\t\t\tbuildSettings = {")
        for key in sorted(settings):
            out.emit(f"\t\t\t\t{key} = {settings[key]};")
        out.emit("\t\t\t};")
        out.emit(f"\t\t\tname = {name};")
        out.emit("\t\t};")
        out.emit("/* End XCBuildConfiguration section */")
        out.emit()

    render_config(project_debug, "Debug", debug_project)
    render_config(project_release, "Release", release_project)
    render_config(app_debug, "Debug", app_debug_settings)
    render_config(app_release, "Release", app_release_settings)
    render_config(test_debug, "Debug", tests_debug_settings)
    render_config(test_release, "Release", tests_release_settings)

    # ---------------- XCConfigurationList ----------------
    out.emit("/* Begin XCConfigurationList section */")
    for list_uuid, label, debug_uuid, release_uuid in (
        (project_config_list, f"PBXProject \"{PROJECT_NAME}\"", project_debug, project_release),
        (app_config_list, f"PBXNativeTarget \"{PROJECT_NAME}\"", app_debug, app_release),
        (test_config_list, f"PBXNativeTarget \"{TEST_TARGET}\"", test_debug, test_release),
    ):
        out.emit(f"\t\t{list_uuid} /* Build configuration list for {label} */ = {{")
        out.emit("\t\t\tisa = XCConfigurationList;")
        out.emit("\t\t\tbuildConfigurations = (")
        out.emit(f"\t\t\t\t{debug_uuid} /* Debug */,")
        out.emit(f"\t\t\t\t{release_uuid} /* Release */,")
        out.emit("\t\t\t);")
        out.emit("\t\t\tdefaultConfigurationIsVisible = 0;")
        out.emit("\t\t\tdefaultConfigurationName = Release;")
        out.emit("\t\t};")
    out.emit("/* End XCConfigurationList section */")
    out.emit()

    out.emit("\t};")
    out.emit(f"\trootObject = {project_object} /* Project object */;")
    out.emit("}")

    scheme = build_scheme(app_target, test_target)
    return "\n".join(out.lines) + "\n", scheme, app_target, test_target


def build_scheme(app_target: str, test_target: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "{XCODE_VERSION}"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "{PROJECT_NAME}.app"
               BlueprintName = "{PROJECT_NAME}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target}"
               BuildableName = "{TEST_TARGET}.xctest"
               BlueprintName = "{TEST_TARGET}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def main() -> None:
    pbxproj, scheme, _, _ = generate()

    if PROJECT_DIR.exists():
        shutil.rmtree(PROJECT_DIR)
    schemes_dir = PROJECT_DIR / "xcshareddata" / "xcschemes"
    schemes_dir.mkdir(parents=True, exist_ok=True)

    (PROJECT_DIR / "project.pbxproj").write_text(pbxproj, encoding="utf-8")
    (schemes_dir / f"{PROJECT_NAME}.xcscheme").write_text(scheme, encoding="utf-8")

    print(f"Generated {PROJECT_DIR}")
    print(f"  {len([r for r in pbxproj.splitlines() if 'in Sources */' in r])} source files")


if __name__ == "__main__":
    main()