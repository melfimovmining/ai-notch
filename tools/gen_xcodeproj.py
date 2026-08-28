#!/usr/bin/env python3
"""Regenerate SideNotch.xcodeproj from whatever is in SideNotch/.

Xcode is not installed on every machine this project gets worked on, so the
project file is generated rather than hand-edited. Run this after adding or
removing a Swift file:

    python3 tools/gen_xcodeproj.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = sorted(p.name for p in (ROOT / "SideNotch").glob("*.swift"))
RESOURCES = ["Resources/AppIcon.icns"]

n = [0]


def uid():
    n[0] += 1
    return "A1B2C3D4E5F6" + format(n[0], "012X")


file_refs = {s: uid() for s in SOURCES + RESOURCES}
build_files = {s: uid() for s in SOURCES + RESOURCES}
plist_ref = uid()
product_ref = uid()
group_root, group_src, group_products = uid(), uid(), uid()
phase_sources, phase_frameworks, phase_resources = uid(), uid(), uid()
target, project = uid(), uid()
cfg_list_project, cfg_list_target = uid(), uid()
cfg_pd, cfg_pr, cfg_td, cfg_tr = uid(), uid(), uid(), uid()


def settings(d, indent):
    pad = "\t" * indent
    out = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            out.append(f"{pad}{k} = (\n" + "".join(f"{pad}\t{i},\n" for i in v) + f"{pad});")
        else:
            out.append(f"{pad}{k} = {v};")
    return "\n".join(out)


common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "SDKROOT": "macosx",
    "SWIFT_VERSION": "5.0",
}
debug_p = dict(common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ['"DEBUG=1"', '"$(inherited)"'],
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
})
release_p = dict(common, **{
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
})
target_common = {
    "CODE_SIGN_IDENTITY": '"-"',
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "SideNotch/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ['"$(inherited)"', '"@executable_path/../Frameworks"'],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.sidenotch.SideNotch",
    "PRODUCT_NAME": '"AI Notch"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}

pbx = []
w = pbx.append
w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {")
w("\t};")
w("\tobjectVersion = 56;")
w("\tobjects = {")

w("\n/* Begin PBXBuildFile section */")
for s in SOURCES:
    w(f"\t\t{build_files[s]} /* {s} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[s]} /* {s} */; }};")
w("/* End PBXBuildFile section */")

w("\n/* Begin PBXFileReference section */")
w(f"\t\t{product_ref} /* AI Notch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \"AI Notch.app\"; sourceTree = BUILT_PRODUCTS_DIR; }};")
for s in SOURCES:
    w(f"\t\t{file_refs[s]} /* {s} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {s}; sourceTree = \"<group>\"; }};")
w(f"\t\t{plist_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
w("/* End PBXFileReference section */")

w("\n/* Begin PBXFrameworksBuildPhase section */")
w(f"\t\t{phase_frameworks} /* Frameworks */ = {{")
w("\t\t\tisa = PBXFrameworksBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXFrameworksBuildPhase section */")

w("\n/* Begin PBXGroup section */")
w(f"\t\t{group_root} = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{group_src} /* SideNotch */,")
w(f"\t\t\t\t{group_products} /* Products */,")
w("\t\t\t);")
w('\t\t\tsourceTree = "<group>";')
w("\t\t};")
w(f"\t\t{group_src} /* SideNotch */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for s in SOURCES:
    w(f"\t\t\t\t{file_refs[s]} /* {s} */,")
w(f"\t\t\t\t{plist_ref} /* Info.plist */,")
w("\t\t\t);")
w("\t\t\tpath = SideNotch;")
w('\t\t\tsourceTree = "<group>";')
w("\t\t};")
w(f"\t\t{group_products} /* Products */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{product_ref} /* AI Notch.app */,")
w("\t\t\t);")
w("\t\t\tname = Products;")
w('\t\t\tsourceTree = "<group>";')
w("\t\t};")
w("/* End PBXGroup section */")

w("\n/* Begin PBXNativeTarget section */")
w(f"\t\t{target} /* SideNotch */ = {{")
w("\t\t\tisa = PBXNativeTarget;")
w(f"\t\t\tbuildConfigurationList = {cfg_list_target} /* Build configuration list for PBXNativeTarget \"SideNotch\" */;")
w("\t\t\tbuildPhases = (")
w(f"\t\t\t\t{phase_sources} /* Sources */,")
w(f"\t\t\t\t{phase_frameworks} /* Frameworks */,")
w(f"\t\t\t\t{phase_resources} /* Resources */,")
w("\t\t\t);")
w("\t\t\tbuildRules = (")
w("\t\t\t);")
w("\t\t\tdependencies = (")
w("\t\t\t);")
w("\t\t\tname = SideNotch;")
w("\t\t\tproductName = SideNotch;")
w(f"\t\t\tproductReference = {product_ref} /* AI Notch.app */;")
w('\t\t\tproductType = "com.apple.product-type.application";')
w("\t\t};")
w("/* End PBXNativeTarget section */")

w("\n/* Begin PBXProject section */")
w(f"\t\t{project} /* Project object */ = {{")
w("\t\t\tisa = PBXProject;")
w("\t\t\tattributes = {")
w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
w("\t\t\t\tLastSwiftUpdateCheck = 1500;")
w("\t\t\t\tLastUpgradeCheck = 1500;")
w("\t\t\t\tTargetAttributes = {")
w(f"\t\t\t\t\t{target} = {{")
w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
w("\t\t\t\t\t};")
w("\t\t\t\t};")
w("\t\t\t};")
w(f"\t\t\tbuildConfigurationList = {cfg_list_project} /* Build configuration list for PBXProject \"SideNotch\" */;")
w('\t\t\tcompatibilityVersion = "Xcode 14.0";')
w("\t\t\tdevelopmentRegion = en;")
w("\t\t\thasScannedForEncodings = 0;")
w("\t\t\tknownRegions = (")
w("\t\t\t\ten,")
w("\t\t\t\tBase,")
w("\t\t\t);")
w(f"\t\t\tmainGroup = {group_root};")
w(f"\t\t\tproductRefGroup = {group_products} /* Products */;")
w('\t\t\tprojectDirPath = "";')
w('\t\t\tprojectRoot = "";')
w("\t\t\ttargets = (")
w(f"\t\t\t\t{target} /* SideNotch */,")
w("\t\t\t);")
w("\t\t};")
w("/* End PBXProject section */")

w("\n/* Begin PBXResourcesBuildPhase section */")
w(f"\t\t{phase_resources} /* Resources */ = {{")
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXResourcesBuildPhase section */")

w("\n/* Begin PBXSourcesBuildPhase section */")
w(f"\t\t{phase_sources} /* Sources */ = {{")
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for s in SOURCES:
    w(f"\t\t\t\t{build_files[s]} /* {s} in Sources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXSourcesBuildPhase section */")

w("\n/* Begin XCBuildConfiguration section */")
for cid, name, d in [(cfg_pd, "Debug", debug_p), (cfg_pr, "Release", release_p),
                     (cfg_td, "Debug", target_common), (cfg_tr, "Release", target_common)]:
    w(f"\t\t{cid} /* {name} */ = {{")
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    w(settings(d, 4))
    w("\t\t\t};")
    w(f"\t\t\tname = {name};")
    w("\t\t};")
w("/* End XCBuildConfiguration section */")

w("\n/* Begin XCConfigurationList section */")
for lid, dbg, rel in [(cfg_list_project, cfg_pd, cfg_pr), (cfg_list_target, cfg_td, cfg_tr)]:
    w(f"\t\t{lid} = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{dbg} /* Debug */,")
    w(f"\t\t\t\t{rel} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
w("/* End XCConfigurationList section */")

w("\t};")
w(f"\trootObject = {project} /* Project object */;")
w("}")

proj = ROOT / "SideNotch.xcodeproj"
(proj / "project.xcworkspace").mkdir(parents=True, exist_ok=True)
(proj / "xcshareddata/xcschemes").mkdir(parents=True, exist_ok=True)
(proj / "project.pbxproj").write_text("\n".join(pbx) + "\n")

(proj / "project.xcworkspace/contents.xcworkspacedata").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n'
    "   </FileRef>\n</Workspace>\n"
)


def buildable(indent):
    pad = " " * indent
    return (
        f'{pad}<BuildableReference\n'
        f'{pad}   BuildableIdentifier = "primary"\n'
        f'{pad}   BlueprintIdentifier = "{target}"\n'
        f'{pad}   BuildableName = "AI Notch.app"\n'
        f'{pad}   BlueprintName = "SideNotch"\n'
        f'{pad}   ReferencedContainer = "container:SideNotch.xcodeproj">\n'
        f'{pad}</BuildableReference>'
    )


scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
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
{buildable(12)}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
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
{buildable(12)}
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
{buildable(12)}
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
(proj / "xcshareddata/xcschemes/SideNotch.xcscheme").write_text(scheme)
print(f"regenerated SideNotch.xcodeproj with {len(SOURCES)} sources: {', '.join(SOURCES)}")
