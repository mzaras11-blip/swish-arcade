#!/usr/bin/env python3
"""Generate SWISH.xcodeproj/project.pbxproj with deterministic UUIDs."""
import hashlib, os

ROOT = os.path.dirname(os.path.abspath(__file__))
SWIFT_FILES = ["SWISHApp.swift", "Models.swift", "GameViewModel.swift",
               "Views.swift", "GameView.swift", "AdManager.swift",
               "StoreManager.swift", "PuzzleGenerator.swift"]
# NOTE: SWISHApp.swift holds the @main entry; create it as a tiny shim below.
JSON_FILES = [f"puzzle-{i:02d}.json" for i in range(1, 13)]
DATA_FILES = ["words.json"]

def uid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

P = {}
def reg(kind, name):
    key = f"{kind}:{name}"
    if key not in P:
        P[key] = uid(key)
    return P[key]

lines = []
A = lines.append

A("// !$*UTF8*$!")
A("{")
A("\tarchiveVersion = 1;")
A("\tclasses = {")
A("\t};")
A("\tobjectVersion = 56;")
A("\tobjects = {")

# ---------- PBXBuildFile ----------
for f in SWIFT_FILES:
    A(f"\t\t{reg('build', f)} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {reg('file', f)} /* {f} */; }};")
for f in JSON_FILES:
    A(f"\t\t{reg('build', f)} /* {f} in Resources */ = {{isa = PBXBuildFile; fileRef = {reg('file', f)} /* {f} */; }};")
for f in DATA_FILES:
    A(f"\t\t{reg('build', f)} /* {f} in Resources */ = {{isa = PBXBuildFile; fileRef = {reg('file', f)} /* {f} */; }};")
A(f"\t\t{reg('build', 'Assets.xcassets')} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {reg('file', 'Assets.xcassets')} /* Assets.xcassets */; }};")

# ---------- PBXFileReference ----------
A(f"\t\t{reg('file', 'SWISH.app')} /* SWISH.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SWISH.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for f in SWIFT_FILES:
    A(f"\t\t{reg('file', f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = \"<group>\"; }};")
A(f"\t\t{reg('file', 'Info.plist')} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
A(f"\t\t{reg('file', 'Assets.xcassets')} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
for f in JSON_FILES:
    A(f"\t\t{reg('file', f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = {f}; sourceTree = \"<group>\"; }};")
for f in DATA_FILES:
    A(f"\t\t{reg('file', f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = Resources/{f}; sourceTree = \"<group>\"; }};")

# ---------- Build phases ----------
A(f"\t\t{reg('phase', 'sources')} /* Sources */ = {{")
A("\t\t\tisa = PBXSourcesBuildPhase;")
A("\t\t\tbuildActionMask = 2147483647;")
A("\t\t\tfiles = (")
for f in SWIFT_FILES:
    A(f"\t\t\t\t{reg('build', f)} /* {f} in Sources */,")
A("\t\t\t);")
A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A("\t\t};")
A(f"\t\t{reg('phase', 'resources')} /* Resources */ = {{")
A("\t\t\tisa = PBXResourcesBuildPhase;")
A("\t\t\tbuildActionMask = 2147483647;")
A("\t\t\tfiles = (")
A(f"\t\t\t\t{reg('build', 'Assets.xcassets')} /* Assets.xcassets in Resources */,")
for f in JSON_FILES:
    A(f"\t\t\t\t{reg('build', f)} /* {f} in Resources */,")
for f in DATA_FILES:
    A(f"\t\t\t\t{reg('build', f)} /* {f} in Resources */,")
A("\t\t\t);")
A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A("\t\t};")
A(f"\t\t{reg('phase', 'frameworks')} /* Frameworks */ = {{")
A("\t\t\tisa = PBXFrameworksBuildPhase;")
A("\t\t\tbuildActionMask = 2147483647;")
A("\t\t\tfiles = (")
A("\t\t\t);")
A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A("\t\t};")

# ---------- PBXGroup ----------
A(f"\t\t{reg('group', 'main')} = {{")
A("\t\t\tisa = PBXGroup;")
A("\t\t\tchildren = (")
A(f"\t\t\t\t{reg('group', 'SWISH')} /* SWISH */,")
A(f"\t\t\t\t{reg('group', 'products')} /* Products */,")
A("\t\t\t);")
A("\t\t\tsourceTree = \"<group>\";")
A("\t\t};")
A(f"\t\t{reg('group', 'products')} /* Products */ = {{")
A("\t\t\tisa = PBXGroup;")
A("\t\t\tchildren = (")
A(f"\t\t\t\t{reg('file', 'SWISH.app')} /* SWISH.app */,")
A("\t\t\t);")
A("\t\t\tname = Products;")
A("\t\t\tsourceTree = \"<group>\";")
A("\t\t};")
A(f"\t\t{reg('group', 'SWISH')} /* SWISH */ = {{")
A("\t\t\tisa = PBXGroup;")
A("\t\t\tchildren = (")
for f in SWIFT_FILES:
    A(f"\t\t\t\t{reg('file', f)} /* {f} */,")
A(f"\t\t\t\t{reg('file', 'Info.plist')} /* Info.plist */,")
A(f"\t\t\t\t{reg('file', 'Assets.xcassets')} /* Assets.xcassets */,")
A(f"\t\t\t\t{reg('group', 'puzzles')} /* puzzles */,")
for f in DATA_FILES:
    A(f"\t\t\t\t{reg('file', f)} /* {f} */,")
A("\t\t\t);")
A("\t\t\tpath = SWISH;")
A("\t\t\tsourceTree = \"<group>\";")
A("\t\t};")
A(f"\t\t{reg('group', 'puzzles')} /* puzzles */ = {{")
A("\t\t\tisa = PBXGroup;")
A("\t\t\tchildren = (")
for f in JSON_FILES:
    A(f"\t\t\t\t{reg('file', f)} /* {f} */,")
A("\t\t\t);")
A("\t\t\tpath = \"Resources/puzzles\";")
A("\t\t\tsourceTree = \"<group>\";")
A("\t\t};")

# ---------- PBXNativeTarget ----------
A(f"\t\t{reg('target', 'SWISH')} /* SWISH */ = {{")
A("\t\t\tisa = PBXNativeTarget;")
A(f"\t\t\tbuildConfigurationList = {reg('cfglist', 'target')} /* Build configuration list for PBXNativeTarget \"SWISH\" */;")
A("\t\t\tbuildPhases = (")
A(f"\t\t\t\t{reg('phase', 'sources')} /* Sources */,")
A(f"\t\t\t\t{reg('phase', 'frameworks')} /* Frameworks */,")
A(f"\t\t\t\t{reg('phase', 'resources')} /* Resources */,")
A("\t\t\t);")
A("\t\t\tbuildRules = (")
A("\t\t\t);")
A("\t\t\tdependencies = (")
A("\t\t\t);")
A("\t\t\tname = SWISH;")
A(f"\t\t\tproductName = SWISH;")
A(f"\t\t\tproductReference = {reg('file', 'SWISH.app')} /* SWISH.app */;")
A("\t\t\tproductType = \"com.apple.product-type.application\";")
A("\t\t};")

# ---------- PBXProject ----------
A(f"\t\t{reg('project', 'proj')} /* Project object */ = {{")
A("\t\t\tisa = PBXProject;")
A("\t\t\tattributes = {")
A("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
A("\t\t\t\tLastSwiftUpdateCheck = 1600;")
A("\t\t\t\tLastUpgradeCheck = 1600;")
A("\t\t\t};")
A(f"\t\t\tbuildConfigurationList = {reg('cfglist', 'project')} /* Build configuration list for PBXProject */;")
A("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
A("\t\t\tdevelopmentRegion = en;")
A("\t\t\thasScannedForEncodings = 0;")
A("\t\t\tknownRegions = (en);")
A(f"\t\t\tmainGroup = {reg('group', 'main')};")
A(f"\t\t\tproductRefGroup = {reg('group', 'products')} /* Products */;")
A("\t\t\tprojectDirPath = \"\";")
A("\t\t\tprojectRoot = \"\";")
A("\t\t\ttargets = (")
A(f"\t\t\t\t{reg('target', 'SWISH')} /* SWISH */,")
A("\t\t\t);")
A("\t\t};")

# ---------- Configurations ----------
def config_block(id_name, display_name, settings):
    # NOTE: display_name must be the standard "Debug"/"Release" — schemes
    # (including Xcode's auto-generated ones) look configurations up by this
    # name. Non-standard names resolve to empty build settings on Xcode 26+,
    # which fails the build with "SWIFT_VERSION '' is unsupported".
    A(f"\t\t{reg('config', id_name)} /* {display_name} */ = {{")
    A("\t\t\tisa = XCBuildConfiguration;")
    A("\t\t\tbuildSettings = {")
    for k, v in settings.items():
        A(f"\t\t\t\t{k} = {v};")
    A("\t\t\t};")
    A(f"\t\t\tname = {display_name};")
    A("\t\t};")

A(f"\t\t{reg('cfglist', 'project')} /* Build configuration list for PBXProject */ = {{")
A("\t\t\tisa = XCConfigurationList;")
A("\t\t\tbuildConfigurations = (")
A(f"\t\t\t\t{reg('config', 'proj-Debug')} /* Debug */,")
A(f"\t\t\t\t{reg('config', 'proj-Release')} /* Release */,")
A("\t\t\t);")
A("\t\t\tdefaultConfigurationIsVisible = 0;")
A("\t\t\tdefaultConfigurationName = Release;")
A("\t\t};")
A(f"\t\t{reg('cfglist', 'target')} /* Build configuration list for PBXNativeTarget \"SWISH\" */ = {{")
A("\t\t\tisa = XCConfigurationList;")
A("\t\t\tbuildConfigurations = (")
A(f"\t\t\t\t{reg('config', 'tgt-Debug')} /* Debug */,")
A(f"\t\t\t\t{reg('config', 'tgt-Release')} /* Release */,")
A("\t\t\t);")
A("\t\t\tdefaultConfigurationIsVisible = 0;")
A("\t\t\tdefaultConfigurationName = Release;")
A("\t\t};")

config_block("proj-Debug", "Debug", {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "MTL_FAST_MATH": "YES",
    "ONLY_ACTIVE_ARCH": "YES",
    "SDKROOT": "iphoneos",
})
config_block("proj-Release", "Release", {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "VALIDATE_PRODUCT": "YES",
})
config_block("tgt-Debug", "Debug", {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": '""',
    "INFOPLIST_FILE": "SWISH/Info.plist",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
    "PRODUCT_BUNDLE_IDENTIFIER": "com.swishgame.app",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": '"1"',
})
config_block("tgt-Release", "Release", {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": '""',
    "INFOPLIST_FILE": "SWISH/Info.plist",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
    "PRODUCT_BUNDLE_IDENTIFIER": "com.swishgame.app",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": '"1"',
})

A("\t};")
A(f"\trootObject = {reg('project', 'proj')} /* Project object */;")
A("}")

outdir = os.path.join(os.path.dirname(ROOT), "SWISH.xcodeproj")
os.makedirs(outdir, exist_ok=True)
with open(os.path.join(outdir, "project.pbxproj"), "w") as f:
    f.write("\n".join(lines) + "\n")
print("wrote", os.path.join(outdir, "project.pbxproj"), f"({len(lines)} lines)")
