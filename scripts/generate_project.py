#!/usr/bin/env python3
"""Generate the checked-in Xcode project without third-party dependencies.

Run after adding/removing Swift files. CI checks that the project matches its
sources. Target/build settings live here; personal signing is set in Xcode.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

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
    if not app_sources or not shared_sources or not widget_sources:
        raise SystemExit("App, shared, and widget source directories must contain Swift files.")
    sources = sorted(set(app_sources + shared_sources + widget_sources))
    file_refs = {}
    resource = "DailyRhythm/Resources/PrivacyInfo.xcprivacy"
    for path in [str(p.relative_to(ROOT)) for p in sources] + [resource]:
        file_refs[path] = obj(
            f"file:{path}", isa="PBXFileReference",
            lastKnownFileType="sourcecode.swift" if path.endswith(".swift") else "text.xml",
            path=path, sourceTree="<group>",
        )
    app_product = obj("product:app", isa="PBXFileReference", explicitFileType="wrapper.application",
                      includeInIndex=0, path="DailyRhythm.app", sourceTree="BUILT_PRODUCTS_DIR")
    widget_product = obj("product:widget", isa="PBXFileReference", explicitFileType="wrapper.app-extension",
                         includeInIndex=0, path="DailyRhythmWidgets.appex", sourceTree="BUILT_PRODUCTS_DIR")
    products = obj("group:products", isa="PBXGroup", children=[app_product, widget_product],
                   name="Products", sourceTree="<group>")
    root_group = obj("group:main", isa="PBXGroup", children=list(file_refs.values()) + [products],
                     sourceTree="<group>")
    package = obj("package:core", isa="XCLocalSwiftPackageReference", relativePath="Packages/DailyRhythmCore")

    common = {
        "APP_GROUP_IDENTIFIER": "group.com.lumetechllc.DailyRhythm",
        "CLANG_ENABLE_MODULES": "YES",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "MARKETING_VERSION": "0.1.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "6.0",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    }

    def configs(name, settings):
        ids = []
        for configuration in ("Debug", "Release"):
            values = dict(settings)
            values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if configuration == "Debug" else "-O"
            values["DEBUG_INFORMATION_FORMAT"] = "dwarf" if configuration == "Debug" else "dwarf-with-dsym"
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
        resources = obj(f"resources:{kind}", isa="PBXResourcesBuildPhase", buildActionMask=2147483647,
                        files=[resource_build], runOnlyForDeploymentPostprocessing=0)
        settings = {
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.lumetechllc.DailyRhythm" + (".Widgets" if kind == "widget" else ""),
            "INFOPLIST_FILE": f"{name}/Info.plist",
            "GENERATE_INFOPLIST_FILE": "NO",
            "CODE_SIGN_ENTITLEMENTS": f"{name}/{name}.entitlements",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"] +
                                     (["@executable_path/../../Frameworks"] if kind == "widget" else []),
        }
        phases = [source_phase, frameworks, resources]
        dependencies = []
        if kind == "widget":
            settings.update({"APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES",
                             "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) WIDGET_EXTENSION"})
        else:
            embed = obj("embed:widget", isa="PBXBuildFile", fileRef=widget_product,
                        settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
            phases.append(obj("phase:embed", isa="PBXCopyFilesBuildPhase", buildActionMask=2147483647,
                              dstPath="", dstSubfolderSpec=13, files=[embed], name="Embed App Extensions",
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
    project = obj("project", isa="PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES",
                   "LastSwiftUpdateCheck": "1600", "LastUpgradeCheck": "1600",
                   "TargetAttributes": {target: {"CreatedOnToolsVersion": "16.0"} for target in targets}},
                  buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0",
                  developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"],
                  mainGroup=root_group, packageReferences=[package], productRefGroup=products,
                  projectDirPath="", projectRoot="", targets=targets)
    pbx = "// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56,
                                       "objects": objects, "rootObject": project}) + "\n"
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
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
    return {
        ROOT / "DailyRhythm.xcodeproj/project.pbxproj": pbx,
        ROOT / "DailyRhythm.xcodeproj/xcshareddata/xcschemes/DailyRhythm.xcscheme": scheme,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for path, content in generate().items():
        if args.check:
            if not path.exists() or path.read_text() != content:
                raise SystemExit(f"Out of date: {path.relative_to(ROOT)}. Run python3 scripts/generate_project.py")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    print("Xcode project is up to date." if args.check else "Generated DailyRhythm.xcodeproj.")
