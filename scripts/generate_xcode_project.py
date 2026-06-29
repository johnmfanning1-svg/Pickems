#!/usr/bin/env python3
"""Generate Pickems.xcodeproj from the current source tree."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_NAME = "Pickems"
BUNDLE_ID = "com.fannypack.pickems"
DEPLOYMENT_TARGET = "17.0"


def uid(seed: str) -> str:
    digest = hashlib.md5(seed.encode()).hexdigest().upper()
    return digest[:24]


APP_SOURCES = sorted(
    str(p.relative_to(ROOT)).replace("\\", "/")
    for p in (ROOT / "Pickems").rglob("*")
    if p.suffix == ".swift"
)
TEST_SOURCES = sorted(
    str(p.relative_to(ROOT)).replace("\\", "/")
    for p in (ROOT / "PickemsTests").rglob("*")
    if p.suffix == ".swift"
)

INFO_PLIST = "Pickems/Resources/Info.plist"
ASSETS = "Pickems/Resources/Assets.xcassets"

# Stable IDs
PROJECT_ID = uid("project")
APP_TARGET_ID = uid("app-target")
TEST_TARGET_ID = uid("test-target")
APP_PRODUCT_ID = uid("app-product")
TEST_PRODUCT_ID = uid("test-product")
MAIN_GROUP_ID = uid("main-group")
APP_GROUP_ID = uid("app-group")
TEST_GROUP_ID = uid("test-group")
SOURCES_PHASE_APP = uid("app-sources")
SOURCES_PHASE_TEST = uid("test-sources")
RESOURCES_PHASE_APP = uid("app-resources")
FRAMEWORKS_PHASE_APP = uid("app-frameworks")
FRAMEWORKS_PHASE_TEST = uid("test-frameworks")
PROJECT_CONFIG_LIST = uid("project-config-list")
APP_CONFIG_LIST = uid("app-config-list")
TEST_CONFIG_LIST = uid("test-config-list")
PROJECT_DEBUG = uid("project-debug")
PROJECT_RELEASE = uid("project-release")
APP_DEBUG = uid("app-debug")
APP_RELEASE = uid("app-release")
TEST_DEBUG = uid("test-debug")
TEST_RELEASE = uid("test-release")


def file_ref_id(path: str) -> str:
    return uid(f"fileref:{path}")


def build_file_id(path: str, target: str) -> str:
    return uid(f"buildfile:{target}:{path}")


def group_id(path: str) -> str:
    return uid(f"group:{path}")


def pbx_file_reference(path: str) -> str:
    file_type = "sourcecode.swift"
    if path.endswith(".plist"):
        file_type = "text.plist.xml"
    elif path.endswith(".xcassets"):
        file_type = "folder.assetcatalog"

    name = Path(path).name
    return f"\t\t{file_ref_id(path)} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {json.dumps(name)}; sourceTree = \"<group>\"; }};"


def collect_groups() -> dict[str, set[str]]:
    groups: dict[str, set[str]] = {"": set()}
    all_paths = APP_SOURCES + TEST_SOURCES + [INFO_PLIST, ASSETS]

    for path in all_paths:
        parts = Path(path).parts
        for i in range(len(parts) - 1):
            group_path = "/".join(parts[: i + 1])
            parent = "/".join(parts[:i]) if i > 0 else ""
            groups.setdefault(parent, set()).add(group_path)
            groups.setdefault(group_path, set())

    groups.setdefault(TEST_GROUP_ID, set())
    return groups


def render_groups() -> list[str]:
    lines: list[str] = []
    groups = collect_groups()

    def children_for(parent: str) -> list[str]:
        child_groups = sorted(groups.get(parent, set()))
        child_files: list[str] = []

        if parent == "":
            child_files.extend([file_ref_id(p) for p in TEST_SOURCES])
            child_files.append(TEST_GROUP_ID)
            child_files.append(APP_GROUP_ID)
            child_files.append(file_ref_id(INFO_PLIST))
            child_files.append(file_ref_id(ASSETS))
        elif parent == "PickemsTests":
            child_files.extend([file_ref_id(p) for p in TEST_SOURCES])
        elif parent.startswith("Pickems"):
            for path in APP_SOURCES + [INFO_PLIST, ASSETS]:
                parts = Path(path).parts
                if "/".join(parts[:-1]) == parent:
                    child_files.append(file_ref_id(path))
            child_groups = [g for g in child_groups if g != parent]

        refs: list[str] = []
        for group in child_groups:
            if parent == "" and group in {"Pickems", "PickemsTests"}:
                refs.append(group_id(group))
            elif parent != "":
                refs.append(group_id(group))
        refs.extend(child_files)
        return refs

    for parent in sorted(groups):
        if parent == "":
            continue
        name = Path(parent).name
        children = children_for(parent)
        child_block = ",\n".join(f"\t\t\t\t{c} /* {Path(c).name if '/' in c or c.endswith('.swift') else name} */" for c in children)
        lines.append(
            f"\t\t{group_id(parent)} /* {name} */ = {{\n"
            f"\t\t\tisa = PBXGroup;\n"
            f"\t\t\tchildren = (\n{child_block}\n\t\t\t);\n"
            f"\t\t\tpath = {json.dumps(name)};\n"
            f"\t\t\tsourceTree = \"<group>\";\n"
            f"\t\t}};"
        )

    root_children = children_for("")
    root_block = ",\n".join(f"\t\t\t\t{c}" for c in root_children)
    lines.append(
        f"\t\t{MAIN_GROUP_ID} = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n{root_block}\n\t\t\t);\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )

    lines.append(
        f"\t\t{TEST_GROUP_ID} /* PickemsTests */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        + ",\n".join(f"\t\t\t\t{file_ref_id(p)} /* {Path(p).name} */" for p in TEST_SOURCES)
        + f"\n\t\t\t);\n\t\t\tpath = PickemsTests;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};"
    )

    return lines


def render_pbxproj() -> str:
    file_refs = []
    for path in APP_SOURCES + TEST_SOURCES + [INFO_PLIST, ASSETS]:
        file_refs.append(pbx_file_reference(path))

    app_build_files = [
        f"\t\t{build_file_id(p, 'app')} /* {Path(p).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id(p)} /* {Path(p).name} */; }};"
        for p in APP_SOURCES
    ]
    app_build_files.append(
        f"\t\t{build_file_id(INFO_PLIST, 'app-plist')} /* Info.plist in Resources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id(INFO_PLIST)} /* Info.plist */; }};"
    )
    app_build_files.append(
        f"\t\t{build_file_id(ASSETS, 'app-assets')} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id(ASSETS)} /* Assets.xcassets */; }};"
    )

    test_build_files = [
        f"\t\t{build_file_id(p, 'test')} /* {Path(p).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id(p)} /* {Path(p).name} */; }};"
        for p in TEST_SOURCES
    ]

    app_sources_entries = "\n".join(
        f"\t\t\t\t{build_file_id(p, 'app')} /* {Path(p).name} in Sources */," for p in APP_SOURCES
    )
    test_sources_entries = "\n".join(
        f"\t\t\t\t{build_file_id(p, 'test')} /* {Path(p).name} in Sources */," for p in TEST_SOURCES
    )

    groups = "\n".join(render_groups())

    return f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(app_build_files)}
{chr(10).join(test_build_files)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t{APP_PRODUCT_ID} /* Pickems.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Pickems.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{TEST_PRODUCT_ID} /* PickemsTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = PickemsTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FRAMEWORKS_PHASE_APP} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{FRAMEWORKS_PHASE_TEST} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{groups}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{APP_TARGET_ID} /* Pickems */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {APP_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "Pickems" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_PHASE_APP} /* Sources */,
\t\t\t\t{FRAMEWORKS_PHASE_APP} /* Frameworks */,
\t\t\t\t{RESOURCES_PHASE_APP} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = Pickems;
\t\t\tproductName = Pickems;
\t\t\tproductReference = {APP_PRODUCT_ID} /* Pickems.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{TEST_TARGET_ID} /* PickemsTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TEST_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "PickemsTests" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_PHASE_TEST} /* Sources */,
\t\t\t\t{FRAMEWORKS_PHASE_TEST} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = PickemsTests;
\t\t\tproductName = PickemsTests;
\t\t\tproductReference = {TEST_PRODUCT_ID} /* PickemsTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{PROJECT_ID} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{APP_TARGET_ID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t\t{TEST_TARGET_ID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t\tTestTargetID = {APP_TARGET_ID};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject "Pickems" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {MAIN_GROUP_ID};
\t\t\tproductRefGroup = {uid('products')} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{APP_TARGET_ID} /* Pickems */,
\t\t\t\t{TEST_TARGET_ID} /* PickemsTests */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{RESOURCES_PHASE_APP} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{build_file_id(ASSETS, 'app-assets')} /* Assets.xcassets in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{SOURCES_PHASE_APP} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_sources_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{SOURCES_PHASE_TEST} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{test_sources_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{PROJECT_DEBUG} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{PROJECT_RELEASE} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{APP_DEBUG} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Pickems/Resources/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{APP_RELEASE} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Pickems/Resources/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{TEST_DEBUG} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}.tests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Pickems.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Pickems";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{TEST_RELEASE} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}.tests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Pickems.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Pickems";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject "Pickems" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{PROJECT_DEBUG} /* Debug */,
\t\t\t\t{PROJECT_RELEASE} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{APP_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "Pickems" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{APP_DEBUG} /* Debug */,
\t\t\t\t{APP_RELEASE} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{TEST_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "PickemsTests" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{TEST_DEBUG} /* Debug */,
\t\t\t\t{TEST_RELEASE} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {PROJECT_ID} /* Project object */;
}}
"""


def main() -> None:
    project_dir = ROOT / f"{PROJECT_NAME}.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    pbxproj = project_dir / "project.pbxproj"
    pbxproj.write_text(render_pbxproj())

    scheme_dir = ROOT / f"{PROJECT_NAME}.xcodeproj/xcshareddata/xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = f"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Scheme
   LastUpgradeVersion = \"1600\"
   version = \"1.7\">
   <BuildAction
      parallelizeBuildables = \"YES\"
      buildImplicitDependencies = \"YES\">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = \"YES\"
            buildForRunning = \"YES\"
            buildForProfiling = \"YES\"
            buildForArchiving = \"YES\"
            buildForAnalyzing = \"YES\">
            <BuildableReference
               BuildableIdentifier = \"primary\"
               BlueprintIdentifier = \"{APP_TARGET_ID}\"
               BuildableName = \"Pickems.app\"
               BlueprintName = \"Pickems\"
               ReferencedContainer = \"container:Pickems.xcodeproj\">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = \"Debug\"
      selectedDebuggerIdentifier = \"Xcode.DebuggerFoundation.Debugger.LLDB\"
      selectedLauncherIdentifier = \"Xcode.DebuggerFoundation.Launcher.LLDB\"
      shouldUseLaunchSchemeArgsEnv = \"YES\">
      <Testables>
         <TestableReference
            skipped = \"NO\"
            parallelizable = \"YES\">
            <BuildableReference
               BuildableIdentifier = \"primary\"
               BlueprintIdentifier = \"{TEST_TARGET_ID}\"
               BuildableName = \"PickemsTests.xctest\"
               BlueprintName = \"PickemsTests\"
               ReferencedContainer = \"container:Pickems.xcodeproj\">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = \"Debug\"
      selectedDebuggerIdentifier = \"Xcode.DebuggerFoundation.Debugger.LLDB\"
      selectedLauncherIdentifier = \"Xcode.DebuggerFoundation.Launcher.LLDB\"
      launchStyle = \"0\"
      useCustomWorkingDirectory = \"NO\"
      ignoresPersistentStateOnLaunch = \"NO\"
      debugDocumentVersioning = \"YES\"
      debugServiceExtension = \"internal\"
      allowLocationSimulation = \"YES\">
      <BuildableProductRunnable
         runnableDebuggingMode = \"0\">
         <BuildableReference
            BuildableIdentifier = \"primary\"
            BlueprintIdentifier = \"{APP_TARGET_ID}\"
            BuildableName = \"Pickems.app\"
            BlueprintName = \"Pickems\"
            ReferencedContainer = \"container:Pickems.xcodeproj\">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
</Scheme>
"""
    (scheme_dir / f"{PROJECT_NAME}.xcscheme").write_text(scheme)
    print(f"Wrote {pbxproj}")
    print(f"Included {len(APP_SOURCES)} app sources and {len(TEST_SOURCES)} test sources")


if __name__ == "__main__":
    main()
