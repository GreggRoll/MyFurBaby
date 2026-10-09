"""Generate a dependency-free Xcode project from the checked-in sources."""
from pathlib import Path
import hashlib, json, plistlib

root = Path(__file__).resolve().parents[1]
project = root / "MyFurBaby.xcodeproj"
project.mkdir(exist_ok=True)
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, value): objects[uid(name)] = value; return uid(name)
def quoted(value): return json.dumps(str(value))
def array(values): return "(" + ", ".join(values) + ")"
def obj(**values): return "{ " + " ".join(f"{key} = {value};" for key, value in values.items()) + " }"
files = {}
for folder in ["App", "Shared", "Widget", "Tests", "Resources"]:
    for path in sorted((root / folder).rglob("*")):
        if path.is_file() and '.xcassets/' not in str(path):
            relative = str(path.relative_to(root))
            extension = path.suffix
            kind = {'.swift': 'sourcecode.swift', '.plist': 'text.plist.xml', '.entitlements': 'text.plist.entitlements', '.ttf': 'file', '.otf': 'file', '.xcprivacy': 'text.xml', '.storekit': 'text', '.mp4': 'video.mp4'}.get(extension, 'text')
            files[relative] = add(relative, obj(isa='PBXFileReference', lastKnownFileType=quoted(kind), path=quoted(relative), sourceTree=quoted('SOURCE_ROOT')))
asset_path = 'Resources/Assets.xcassets'
files[asset_path] = add(asset_path, obj(isa='PBXFileReference', lastKnownFileType=quoted('folder.assetcatalog'), path=quoted(asset_path), sourceTree=quoted('SOURCE_ROOT')))
groups = []
for folder in ['App', 'Shared', 'Widget', 'Tests', 'Resources']:
    groups.append(add('group-' + folder, obj(isa='PBXGroup', children=array([value for path, value in files.items() if path.startswith(folder + '/')]), name=quoted(folder), sourceTree=quoted('<group>'))))
targets = {}
products = []
configs = ['Debug', 'Release']
common = {'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SDKROOT': 'iphoneos', 'SWIFT_VERSION': '5.0', 'CLANG_ENABLE_MODULES': 'YES', 'CODE_SIGN_STYLE': 'Automatic', 'CURRENT_PROJECT_VERSION': '12', 'MARKETING_VERSION': '1.0', 'TARGETED_DEVICE_FAMILY': quoted('1,2'), 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES'}
def configuration_list(name, settings):
    refs = []
    for config in configs:
        build = dict(common); build.update(settings)
        build['SWIFT_OPTIMIZATION_LEVEL'] = quoted('-Onone' if config == 'Debug' else '-O')
        build['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = quoted('DEBUG' if config == 'Debug' else '')
        build['DEBUG_INFORMATION_FORMAT'] = quoted('dwarf' if config == 'Debug' else 'dwarf-with-dsym')
        if config == 'Debug': build['ENABLE_TESTABILITY'] = 'YES'
        refs.append(add(name + '-config-' + config, obj(isa='XCBuildConfiguration', name=quoted(config), buildSettings=obj(**build))))
    return add(name + '-configs', obj(isa='XCConfigurationList', buildConfigurations=array(refs), defaultConfigurationIsVisible='0', defaultConfigurationName=quoted('Release')))

for name, suffix, product_type in [('MyFurBaby', 'app', 'application'), ('FurBabyWidget', 'appex', 'app-extension'), ('MyFurBabyTests', 'xctest', 'bundle.unit-test')]:
    product = add(name + '-product', obj(isa='PBXFileReference', explicitFileType=quoted('wrapper.application' if suffix == 'app' else 'wrapper.app-extension' if suffix == 'appex' else 'wrapper.cfbundle'), includeInIndex='0', path=quoted(name + '.' + suffix), sourceTree=quoted('BUILT_PRODUCTS_DIR')))
    products.append(product)
    source_paths = [path for path in files if path.endswith('.swift') and (path.startswith('App/') or path.startswith('Shared/'))] if name == 'MyFurBaby' else [path for path in files if path.endswith('.swift') and (path.startswith('Shared/') or path.startswith('Widget/'))] if name == 'FurBabyWidget' else [path for path in files if path.startswith('Tests/') and path.endswith('.swift')]
    sources = [add(name + '-source-' + path, obj(isa='PBXBuildFile', fileRef=files[path])) for path in source_paths]
    resource_paths = [asset_path, 'Resources/PrivacyInfo.xcprivacy', 'Resources/WidgetAnimation-LICENSE.txt', 'Resources/FurTimerMask.otf'] if name == 'MyFurBaby' else [asset_path, 'Resources/FurTimerMask.otf', 'Resources/WidgetAnimation-LICENSE.txt', 'Resources/PrivacyInfo.xcprivacy'] if name == 'FurBabyWidget' else []
    if name == 'MyFurBaby': resource_paths += ['Resources/FurMotionTemplate.ttf'] + [path for path in files if path.startswith('Resources/Onboarding/') and path.endswith('.mp4')]
    if name in ['MyFurBaby', 'FurBabyWidget']: resource_paths += ['Resources/FurCycle3-Regular.ttf', 'Resources/FurCycle4-Regular.ttf', 'Resources/FurLoop12-Regular.ttf', 'Resources/FurLoop13-Regular.ttf', 'Resources/FurLoop14-Regular.ttf', 'Resources/FurIdle12-Regular.ttf', 'Resources/FurIdle13-Regular.ttf', 'Resources/FurIdle14-Regular.ttf', 'Resources/FurLoop22-Regular.ttf', 'Resources/FurRest22-Regular.ttf', 'Resources/FurLoop23-Regular.ttf', 'Resources/FurRest23-Regular.ttf', 'Resources/FurLoop24-Regular.ttf', 'Resources/FurRest24-Regular.ttf']
    resources = [add(name + '-resource-' + path, obj(isa='PBXBuildFile', fileRef=files[path])) for path in resource_paths if path in files]
    phases = [add(name + '-sources', obj(isa='PBXSourcesBuildPhase', buildActionMask='2147483647', files=array(sources), runOnlyForDeploymentPostprocessing='0')), add(name + '-frameworks', obj(isa='PBXFrameworksBuildPhase', buildActionMask='2147483647', files='()', runOnlyForDeploymentPostprocessing='0')), add(name + '-resources', obj(isa='PBXResourcesBuildPhase', buildActionMask='2147483647', files=array(resources), runOnlyForDeploymentPostprocessing='0'))]
    dependencies = []
    settings = {'PRODUCT_NAME': quoted('$(TARGET_NAME)'), 'PRODUCT_BUNDLE_IDENTIFIER': quoted('com.gregadams.myfurbaby' if name == 'MyFurBaby' else 'com.gregadams.myfurbaby.widget' if name == 'FurBabyWidget' else 'com.gregadams.myfurbaby.tests'), 'GENERATE_INFOPLIST_FILE': 'YES', 'SWIFT_EMIT_LOC_STRINGS': 'YES'}
    if name == 'MyFurBaby':
        settings.update({'INFOPLIST_FILE': quoted('App/Info.plist'), 'CODE_SIGN_ENTITLEMENTS': quoted('App/App.entitlements'), 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES'})
        embed = add('embed-widget-file', obj(isa='PBXBuildFile', fileRef=uid('FurBabyWidget-product'), settings=obj(ATTRIBUTES='(RemoveHeadersOnCopy)')))
        phases.append(add('embed-widget', obj(isa='PBXCopyFilesBuildPhase', buildActionMask='2147483647', dstPath=quoted(''), dstSubfolderSpec='13', files=array([embed]), name=quoted('Embed App Extensions'), runOnlyForDeploymentPostprocessing='0')))
    elif name == 'FurBabyWidget': settings.update({'INFOPLIST_FILE': quoted('Widget/Info.plist'), 'CODE_SIGN_ENTITLEMENTS': quoted('Widget/Widget.entitlements'), 'APPLICATION_EXTENSION_API_ONLY': 'YES', 'SKIP_INSTALL': 'YES'})
    else: settings.update({'TEST_HOST': quoted('$(BUILT_PRODUCTS_DIR)/MyFurBaby.app/MyFurBaby'), 'BUNDLE_LOADER': quoted('$(TEST_HOST)'), 'SKIP_INSTALL': 'YES'})
    if name in ['MyFurBaby', 'MyFurBabyTests']:
        dependency_name = 'FurBabyWidget' if name == 'MyFurBaby' else 'MyFurBaby'
        proxy = add(name + '-proxy', obj(isa='PBXContainerItemProxy', containerPortal=uid('project'), proxyType='1', remoteGlobalIDString=uid(dependency_name + '-target'), remoteInfo=quoted(dependency_name)))
        dependencies.append(add(name + '-dependency', obj(isa='PBXTargetDependency', target=uid(dependency_name + '-target'), targetProxy=proxy)))
    targets[name] = add(name + '-target', obj(isa='PBXNativeTarget', buildConfigurationList=configuration_list(name, settings), buildPhases=array(phases), buildRules='()', dependencies=array(dependencies), name=quoted(name), productName=quoted(name), productReference=product, productType=quoted('com.apple.product-type.' + product_type)))
product_group = add('products-group', obj(isa='PBXGroup', children=array(products), name=quoted('Products'), sourceTree=quoted('<group>')))
main_group = add('main-group', obj(isa='PBXGroup', children=array(groups + [product_group]), sourceTree=quoted('<group>')))
project_id = add('project', obj(isa='PBXProject', attributes=obj(BuildIndependentTargetsInParallel='YES', LastUpgradeCheck='2630'), buildConfigurationList=configuration_list('project', {}), compatibilityVersion=quoted('Xcode 14.0'), developmentRegion='en', hasScannedForEncodings='0', knownRegions='(en, Base)', mainGroup=main_group, productRefGroup=product_group, projectDirPath=quoted(''), projectRoot=quoted(''), targets=array(list(targets.values()))))
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{key} = {value};' for key, value in objects.items()) + '\n}; rootObject = ' + project_id + '; }\n')

app_info = {'CFBundleDisplayName': 'My Fur Baby', 'ITSAppUsesNonExemptEncryption': False, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'], 'UISupportedInterfaceOrientations~ipad': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'], 'CFBundleURLTypes': [{'CFBundleURLSchemes': ['myfurbaby']}], 'NSPhotoLibraryAddUsageDescription': 'Save your Fur Baby photo adventures to your photo library.', 'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True}, 'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False}}
widget_info = {'CFBundleDisplayName': 'My Fur Baby', 'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}, 'UIAppFonts': ['FurTimerMask.otf', 'FurCycle3-Regular.ttf', 'FurCycle4-Regular.ttf', 'FurLoop12-Regular.ttf', 'FurLoop13-Regular.ttf', 'FurLoop14-Regular.ttf', 'FurIdle12-Regular.ttf', 'FurIdle13-Regular.ttf', 'FurIdle14-Regular.ttf', 'FurLoop22-Regular.ttf', 'FurRest22-Regular.ttf', 'FurLoop23-Regular.ttf', 'FurRest23-Regular.ttf', 'FurLoop24-Regular.ttf', 'FurRest24-Regular.ttf']}
for path, data in [('App/Info.plist', app_info), ('Widget/Info.plist', widget_info)]:
    with (root / path).open('wb') as file: plistlib.dump(data, file)

scheme_dir = project / 'xcshareddata/xcschemes'; scheme_dir.mkdir(parents=True, exist_ok=True)
def reference(name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[name]}" BuildableName="{name}.{"app" if name == "MyFurBaby" else "xctest"}" BlueprintName="{name}" ReferencedContainer="container:MyFurBaby.xcodeproj" />'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference('MyFurBaby')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference('MyFurBabyTests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('MyFurBaby')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('MyFurBaby')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug" /><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES" /></Scheme>'''
(scheme_dir / 'MyFurBaby.xcscheme').write_text(scheme)
(scheme_dir / 'MyFurBabyStoreKit.xcscheme').write_text(scheme.replace('</LaunchAction>', '<StoreKitConfigurationFileReference identifier="../../../Resources/Products.storekit" /></LaunchAction>'))
print('Generated MyFurBaby.xcodeproj')
