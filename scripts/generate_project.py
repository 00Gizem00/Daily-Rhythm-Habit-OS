#!/usr/bin/env python3
"""Generate the checked-in Xcode project without third-party dependencies.

Run after adding/removing Swift files. CI checks that the project matches its
sources. Target/build settings, including the shared signing team, live here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

from check_source_membership import SOURCE_DIRECTORIES, source_fingerprint

ROOT = Path(__file__).resolve().parents[1]


def uid(name: str) -> str:
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def encode(value, indent=0):
    tab = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join(
            f'{tab}\t{json.dumps(str(key))} = {encode(item, indent + 1)};\n'
            for key, item in value.items()
        ) + tab + "}"
    if isinstance(value, list):
        return "(\n" + "".join(
            f"{tab}\t{encode(item, indent + 1)},\n" for item in value
        ) + tab + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value)


def generate():
    objects = {}

    def obj(identifier, **fields):
        key = uid(identifier)
        objects[key] = fields
        return key

    app_sources = sorted(ROOT.glob("DailyRhythm/App/**/*.swift"))
    shared_sources = sorted(ROOT.glob("DailyRhythm/Shared/**/*.swift"))
    widget_sources = sorted(ROOT.glob("DailyRhythmWidgets/**/*.swift"))
    schema_test_sources = sorted(ROOT.glob("DailyRhythmSchemaTests/**/*.swift"))
    if not app_sources or not shared_sources or not widget_sources:
        raise SystemExit("App, shared, and widget source directories must contain Swift files.")
    sources = sorted(set(app_sources + shared_sources + widget_sources + schema_test_sources))
    file_refs = {}
    resource = "DailyRhythm/Resources/PrivacyInfo.xcprivacy"
    assets = "DailyRhythm/Resources/Assets.xcassets"
    launch_screen = "DailyRhythm/Resources/LaunchScreen.storyboard"
    for path in [str(p.relative_to(ROOT)) for p in sources] + [resource, assets, launch_screen]:
        file_refs[path] = obj(
            f"file:{path}", isa="PBXFileReference",
            lastKnownFileType=("sourcecode.swift" if path.endswith(".swift") else
                               "folder.assetcatalog" if path.endswith(".xcassets") else
                               "file.storyboard" if path.endswith(".storyboard") else "text.xml"),
            path=path, sourceTree="<group>",
        )
    app_product = obj("product:app", isa="PBXFileReference", explicitFileType="wrapper.application",
                      includeInIndex=0, path="DailyRhythm.app", sourceTree="BUILT_PRODUCTS_DIR")
    widget_product = obj("product:widget", isa="PBXFileReference", explicitFileType="wrapper.app-extension",
                         includeInIndex=0, path="DailyRhythmWidgets.appex", sourceTree="BUILT_PRODUCTS_DIR")
    tests_product = obj("product:schema-tests", isa="PBXFileReference", explicitFileType="wrapper.cfbundle",
                        includeInIndex=0, path="DailyRhythmSchemaTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    products = obj("group:products", isa="PBXGroup", children=[app_product, widget_product, tests_product],
                   name="Products", sourceTree="<group>")
    root_group = obj("group:main", isa="PBXGroup", children=list(file_refs.values()) + [products],
                     sourceTree="<group>")
    package = obj("package:core", isa="XCLocalSwiftPackageReference", relativePath="Packages/DailyRhythmCore")

    common = {
        "APP_GROUP_IDENTIFIER": "group.com.lumetechllc.DailyRhythm",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "CODE_SIGN_STYLE": "Automatic",
        # LumeTech owns both bundle IDs and the shared App Group. Keep all targets
        # on this team when regenerating the project after source changes.
        "DEVELOPMENT_TEAM": "U54BLJMYG6",
        "CURRENT_PROJECT_VERSION": "3",
        "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "MARKETING_VERSION": "0.1.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "6.0",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
    }

    def configs(name, settings):
        ids = []
        for configuration in ("Debug", "Release"):
            values = dict(settings)
            values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if configuration == "Debug" else "-O"
            values["DEBUG_INFORMATION_FORMAT"] = "dwarf" if configuration == "Debug" else "dwarf-with-dsym"
            if name == "project":
                # Match SwiftPM's active-architecture Debug builds. Otherwise a
                # selected arm64 Simulator can make the app/widget ask for an
                # x86_64 dependency slice that the package did not build.
                values["ONLY_ACTIVE_ARCH"] = "YES" if configuration == "Debug" else "NO"
                if configuration == "Release":
                    values["SWIFT_COMPILATION_MODE"] = "wholemodule"
                else:
                    # Keep Debug symbols when embedding the already signed widget.
                    # Copy-phase stripping cannot modify its signed binaries.
                    values["COPY_PHASE_STRIP"] = "NO"
            if configuration == "Debug":
                values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = (
                    values.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "$(inherited)") + " DEBUG"
                )
                values["ENABLE_TESTABILITY"] = "YES"
            ids.append(obj(f"config:{name}:{configuration}", isa="XCBuildConfiguration",
                           buildSettings=values, name=configuration))
        return obj(f"configs:{name}", isa="XCConfigurationList", buildConfigurations=ids,
                   defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

    project_configs = configs("project", common)

    def membership_guard(kind, paths):
        # The expected value is embedded in the loaded build graph, not read from
        # disk at build time. Thus an old Xcode session also detects new sources.
        script = ('/usr/bin/python3 -B "$SRCROOT/scripts/check_source_membership.py" '
                  f'--root "$SRCROOT" --target {kind} '
                  f'--expected {source_fingerprint(ROOT, paths)}\n')
        return obj(f"source-guard:{kind}", isa="PBXShellScriptBuildPhase",
                   buildActionMask=2147483647, files=[],
                   inputPaths=["$(SRCROOT)/scripts/check_source_membership.py"] +
                              [f"$(SRCROOT)/{p}" for p in SOURCE_DIRECTORIES[kind]],
                   outputPaths=[], name="Check loaded Swift source membership",
                   shellPath="/bin/sh", shellScript=script,
                   alwaysOutOfDate=1, runOnlyForDeploymentPostprocessing=0)

    targets = []
    for kind, name, paths, product in (
        ("app", "DailyRhythm", app_sources + shared_sources, app_product),
        ("widget", "DailyRhythmWidgets", widget_sources + shared_sources, widget_product),
    ):
        source_builds = []
        for p in paths:
            path = str(p.relative_to(ROOT))
            source_builds.append(obj(f"build:{kind}:{path}", isa="PBXBuildFile", fileRef=file_refs[path]))
        source_phase = obj(f"sources:{kind}", isa="PBXSourcesBuildPhase", buildActionMask=2147483647,
                           files=source_builds, runOnlyForDeploymentPostprocessing=0)
        package_product = obj(f"packageproduct:{kind}", isa="XCSwiftPackageProductDependency",
                              package=package, productName="DailyRhythmCore")
        package_build = obj(f"packagebuild:{kind}", isa="PBXBuildFile", productRef=package_product)
        frameworks = obj(f"frameworks:{kind}", isa="PBXFrameworksBuildPhase", buildActionMask=2147483647,
                         files=[package_build], runOnlyForDeploymentPostprocessing=0)
        resource_build = obj(f"resource:{kind}", isa="PBXBuildFile", fileRef=file_refs[resource])
        resource_builds = [resource_build]
        if kind == "app":
            resource_builds.append(obj("resource:app:assets", isa="PBXBuildFile", fileRef=file_refs[assets]))
            resource_builds.append(obj("resource:app:launch-screen", isa="PBXBuildFile", fileRef=file_refs[launch_screen]))
        resources = obj(f"resources:{kind}", isa="PBXResourcesBuildPhase", buildActionMask=2147483647,
                        files=resource_builds, runOnlyForDeploymentPostprocessing=0)
        settings = {
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.lumetechllc.DailyRhythm" + (".Widgets" if kind == "widget" else ""),
            "INFOPLIST_FILE": f"{name}/Info.plist",
            "GENERATE_INFOPLIST_FILE": "NO",
            "CODE_SIGN_ENTITLEMENTS": f"{name}/{name}.entitlements",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"] +
                                     (["@executable_path/../../Frameworks"] if kind == "widget" else []),
        }
        phases = [membership_guard(kind, paths), source_phase, frameworks, resources]
        dependencies = []
        if kind == "widget":
            settings.update({"APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES",
                             "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) WIDGET_EXTENSION"})
        else:
            settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
            embed = obj("embed:widget", isa="PBXBuildFile", fileRef=widget_product,
                        settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
            phases.append(obj("phase:embed", isa="PBXCopyFilesBuildPhase", buildActionMask=2147483647,
                              dstPath="", dstSubfolderSpec=13, files=[embed], name="Embed Foundation Extensions",
                              runOnlyForDeploymentPostprocessing=0))
            proxy = obj("proxy:widget", isa="PBXContainerItemProxy", containerPortal=uid("project"),
                        proxyType=1, remoteGlobalIDString=uid("target:widget"), remoteInfo="DailyRhythmWidgets")
            dependencies.append(obj("dependency:widget", isa="PBXTargetDependency",
                                    target=uid("target:widget"), targetProxy=proxy))
        targets.append(obj(f"target:{kind}", isa="PBXNativeTarget", buildConfigurationList=configs(kind, settings),
                           buildPhases=phases, buildRules=[], dependencies=dependencies, name=name,
                           packageProductDependencies=[package_product], productName=name, productReference=product,
                           productType="com.apple.product-type.application" if kind == "app"
                           else "com.apple.product-type.app-extension"))
    # Opt-in iOS 27 out-of-process App Intents tests. Not part of the product scheme.
    test_builds = [obj(f"build:schema-tests:{p.relative_to(ROOT)}", isa="PBXBuildFile",
                       fileRef=file_refs[str(p.relative_to(ROOT))]) for p in schema_test_sources]
    test_sources = obj("sources:schema-tests", isa="PBXSourcesBuildPhase", buildActionMask=2147483647,
                       files=test_builds, runOnlyForDeploymentPostprocessing=0)
    test_frameworks = obj("frameworks:schema-tests", isa="PBXFrameworksBuildPhase", buildActionMask=2147483647,
                          files=[], runOnlyForDeploymentPostprocessing=0)
    app_proxy = obj("proxy:schema-tests-app", isa="PBXContainerItemProxy", containerPortal=uid("project"),
                    proxyType=1, remoteGlobalIDString=uid("target:app"), remoteInfo="DailyRhythm")
    app_dependency = obj("dependency:schema-tests-app", isa="PBXTargetDependency",
                         target=uid("target:app"), targetProxy=app_proxy)
    test_settings = {
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.lumetechllc.DailyRhythm.SchemaTests",
        "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "DailyRhythm",
        "IPHONEOS_DEPLOYMENT_TARGET": "27.0", "SKIP_INSTALL": "YES",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
    }
    targets.append(obj("target:schema-tests", isa="PBXNativeTarget",
                       buildConfigurationList=configs("schema-tests", test_settings),
                       buildPhases=[membership_guard("schema-tests", schema_test_sources), test_sources, test_frameworks],
                       buildRules=[], dependencies=[app_dependency],
                       name="DailyRhythmSchemaTests", productName="DailyRhythmSchemaTests",
                       productReference=tests_product, productType="com.apple.product-type.bundle.ui-testing"))
    project = obj("project", isa="PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES",
                   "LastSwiftUpdateCheck": "1600", "LastUpgradeCheck": "2700",
                   "TargetAttributes": {target: {"CreatedOnToolsVersion": "16.0"} for target in targets}},
                  buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0",
                  developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"],
                  mainGroup=root_group, packageReferences=[package], productRefGroup=products,
                  projectDirPath="", projectRoot="", targets=targets)
    pbx = "// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56,
                                       "objects": objects, "rootObject": project}) + "\n"
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target:app')}" BuildableName="DailyRhythm.app" BlueprintName="DailyRhythm" ReferencedContainer="container:DailyRhythm.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target:app')}" BuildableName="DailyRhythm.app" BlueprintName="DailyRhythm" ReferencedContainer="container:DailyRhythm.xcodeproj"/>
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target:app')}" BuildableName="DailyRhythm.app" BlueprintName="DailyRhythm" ReferencedContainer="container:DailyRhythm.xcodeproj"/>
    </BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    test_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:schema-tests")}" BuildableName="DailyRhythmSchemaTests.xctest" BlueprintName="DailyRhythmSchemaTests" ReferencedContainer="container:DailyRhythm.xcodeproj"/>'
    test_scheme = scheme.replace("<Testables/>", f'<Testables><TestableReference skipped="NO">{test_reference}</TestableReference></Testables>')
    test_scheme = test_scheme.replace("</BuildActionEntries>", f'<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{test_reference}</BuildActionEntry></BuildActionEntries>')
    return {
        ROOT / "DailyRhythm.xcodeproj/project.pbxproj": pbx,
        ROOT / "DailyRhythm.xcodeproj/xcshareddata/xcschemes/DailyRhythm.xcscheme": scheme,
        ROOT / "DailyRhythm.xcodeproj/xcshareddata/xcschemes/DailyRhythmSchemaTests.xcscheme": test_scheme,
    }


def write_if_changed(path: Path, content: str) -> bool:
    """Publish a complete file in one rename; leave unchanged files untouched."""
    if path.exists() and path.read_text() == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    changed = False
    for path, content in generate().items():
        if args.check:
            if not path.exists() or path.read_text() != content:
                raise SystemExit(f"Out of date: {path.relative_to(ROOT)}. Run python3 scripts/generate_project.py")
        else:
            changed = write_if_changed(path, content) or changed
    if changed:
        print("Generated DailyRhythm.xcodeproj. If it is open in Xcode, use File > Close Project "
              "and reopen it before building. Keep the current run destination.")
    else:
        print("Xcode project is up to date.")
