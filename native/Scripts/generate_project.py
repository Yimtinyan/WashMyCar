#!/usr/bin/env python3
"""Generate a self-contained Xcode project with the Python standard library.

Run from any directory. No XcodeGen, CocoaPods or downloaded dependencies needed.
"""
import hashlib
import json
import os
import pathlib
import plistlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = ROOT / "WashMyCar.xcodeproj"
CONFIG = ROOT / "Config"
CONFIG.mkdir(exist_ok=True)
PROJECT.mkdir(exist_ok=True)

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

objects = {}
def add(key, isa, **fields):
    objects[uid(key)] = {"isa": isa, **fields}
    return uid(key)

def raw(value):
    if isinstance(value, dict):
        return "{ " + " ".join(f"{quote(k)} = {raw(v)};" for k,v in value.items()) + " }"
    if isinstance(value, list):
        return "( " + ", ".join(raw(x) for x in value) + ", )" if value else "()"
    if isinstance(value, int):
        return str(value)
    return quote(value)

files = {}
def ref(path):
    if path not in files:
        extension = pathlib.Path(path).suffix
        kind = {".swift": "sourcecode.swift", ".json": "text.json", ".xcassets": "folder.assetcatalog"}.get(extension, "text")
        files[path] = add("file:"+path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")
    return files[path]

targets = [
    {"name": "WashMyCar", "folder": "iOS", "product": "WashMyCar.app", "type": "com.apple.product-type.application", "sdk": "iphoneos", "platforms": "iphoneos iphonesimulator", "family": "1,2", "bundle": "com.yimtinyan.WashMyCar"},
    {"name": "WashMyCarWatch", "folder": "Watch", "product": "WashMyCarWatch.app", "type": "com.apple.product-type.application", "sdk": "watchos", "platforms": "watchos watchsimulator", "family": "4", "bundle": "com.yimtinyan.WashMyCar.watchkitapp"},
    {"name": "WashWidgets", "folder": "Widgets", "product": "WashWidgets.appex", "type": "com.apple.product-type.app-extension", "sdk": "iphoneos", "platforms": "iphoneos iphonesimulator", "family": "1,2", "bundle": "com.yimtinyan.WashMyCar.widgets"},
]
shared = sorted(str(p.relative_to(ROOT)) for p in (ROOT/"Shared").glob("*.swift"))
platform = ["Platform/Connectivity.swift"]
products = []
for t in targets:
    name = t["name"]
    source_paths = sorted(str(p.relative_to(ROOT)) for p in (ROOT/t["folder"]).glob("*.swift"))
    source_paths += shared if t["folder"] != "Widgets" else ["Shared/JSON.swift"]
    if t["folder"] in ("iOS", "Watch"):
        source_paths += platform
    source_files = [add(name+":"+path, "PBXBuildFile", fileRef=ref(path)) for path in source_paths]
    phases = [add(name+":sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=source_files, runOnlyForDeploymentPostprocessing=0)]
    phases.append(add(name+":frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0))
    resources = []
    if t["folder"] == "iOS":
        resources = [add(name+":resource:"+path, "PBXBuildFile", fileRef=ref(path)) for path in ["iOS/Assets.xcassets", "Resources/Seed.json"]]
    phases.append(add(name+":resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0))
    dependencies = []
    if t["folder"] == "iOS":
        for dependency, folder, subfolder in [("WashMyCarWatch", "$(CONTENTS_FOLDER_PATH)/Watch", 16), ("WashWidgets", "", 13)]:
            embedded = add(name+":embed:"+dependency, "PBXBuildFile", fileRef=uid(dependency+":product"), platformFilter="ios", settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
            phases.append(add(name+":copy:"+dependency, "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath=folder, dstSubfolderSpec=subfolder, files=[embedded], name="Embed "+dependency, runOnlyForDeploymentPostprocessing=0))
            dependencies.append(add(name+":depends:"+dependency, "PBXTargetDependency", target=uid(dependency+":target"), platformFilter="ios"))
    product = add(name+":product", "PBXFileReference", explicitFileType="wrapper.app-extension" if name == "WashWidgets" else "wrapper.application", includeInIndex=0, path=t["product"], sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product)
    info = {
        "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)", "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)", "CFBundleDisplayName": "WashMyCar",
        "CFBundlePackageType": "XPC!" if name == "WashWidgets" else "APPL",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    }
    if name == "WashMyCar":
        info.update({"UILaunchScreen": {}, "CFBundleURLTypes": [{"CFBundleURLName": t["bundle"], "CFBundleURLSchemes": ["washmycar"]}], "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]})
    elif name == "WashMyCarWatch":
        info.update({"WKApplication": True, "WKCompanionAppBundleIdentifier": "com.yimtinyan.WashMyCar", "WKRunsIndependentlyOfCompanionApp": False})
    else:
        info["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}
    (CONFIG/(name+"-Info.plist")).write_bytes(plistlib.dumps(info, sort_keys=False))
    settings = {
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": t["bundle"],
        "INFOPLIST_FILE": "Config/"+name+"-Info.plist", "GENERATE_INFOPLIST_FILE": "YES",
        "SDKROOT": t["sdk"], "SUPPORTED_PLATFORMS": t["platforms"], "TARGETED_DEVICE_FAMILY": t["family"],
        "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "targeted", "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "0.1.0", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "SWIFT_EMIT_LOC_STRINGS": "YES", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "WATCHOS_DEPLOYMENT_TARGET": "10.0",
        "ENABLE_PREVIEWS": "YES", "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    }
    if os.environ.get("WASHMYCAR_TEAM_ID"):
        settings["DEVELOPMENT_TEAM"] = os.environ["WASHMYCAR_TEAM_ID"]
    if name == "WashMyCar":
        settings.update({"INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES", "SUPPORTS_MACCATALYST": "YES", "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER": "NO", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor"})
    else:
        settings["SKIP_INSTALL"] = "YES"
    if name in ("WashMyCar", "WashWidgets"):
        entitlement = {"com.apple.security.application-groups": ["group.com.yimtinyan.WashMyCar"]}
        (CONFIG/(name+".entitlements")).write_bytes(plistlib.dumps(entitlement))
        settings["CODE_SIGN_ENTITLEMENTS"] = "Config/"+name+".entitlements"
        settings["SUPPORTS_MACCATALYST"] = "YES"
    configurations = []
    for config in ["Debug", "Release"]:
        build = dict(settings)
        build.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym"})
        if config == "Debug": build["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
        configurations.append(add(name+":"+config, "XCBuildConfiguration", buildSettings=build, name=config))
    configuration_list = add(name+":configurations", "XCConfigurationList", buildConfigurations=configurations, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    add(name+":target", "PBXNativeTarget", buildConfigurationList=configuration_list, buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name, productReference=product, productType=t["type"])

project_configurations = []
for config in ["Debug", "Release"]:
    project_configurations.append(add("project:"+config, "XCBuildConfiguration", name=config, buildSettings={"CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "SWIFT_VERSION": "5.0", "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "DEBUG=1"] if config == "Debug" else ["$(inherited)"]}))
project_list = add("project:configurations", "XCConfigurationList", buildConfigurations=project_configurations, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
product_group = add("products", "PBXGroup", children=products, name="Products", sourceTree="<group>")
main_group = add("main", "PBXGroup", children=list(files.values()) + [product_group], sourceTree="<group>")
project_id = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2700", "TargetAttributes": {uid(t["name"]+":target"): {"CreatedOnToolsVersion": "27.2"} for t in targets}}, buildConfigurationList=project_list, compatibilityVersion="Xcode 14.0", developmentRegion="zh-Hans", hasScannedForEncodings=0, knownRegions=["zh-Hans", "en", "Base"], mainGroup=main_group, productRefGroup=product_group, projectDirPath="", projectRoot="", targets=[uid(t["name"]+":target") for t in targets])
body = "// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 56;\nobjects = {\n"
body += "\n".join(f"{key} = {raw(value)};" for key,value in objects.items())
body += f"\n}};\nrootObject = {project_id};\n}}\n"
(PROJECT/"project.pbxproj").write_text(body)

schemes = PROJECT/"xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
for t in targets[:2]:
    name = t["name"]
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name+":target")}" BuildableName="{t["product"]}" BlueprintName="{name}" ReferencedContainer="container:WashMyCar.xcodeproj"/>'
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (schemes/(name+".xcscheme")).write_text(scheme)
print(PROJECT)
