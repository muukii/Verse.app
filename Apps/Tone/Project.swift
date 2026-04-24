import ProjectDescription
import ProjectDescriptionHelpers

let toneVersionInfoPlistKeys: [String: Plist.Value] = [
  "CFBundleShortVersionString": "$(APP_SHORT_VERSION)",
  "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
]

let toneInfoPlist: InfoPlist = .extendingDefault(with: toneVersionInfoPlistKeys.merging([
  "BGTaskSchedulerPermittedIdentifiers": .array([
    "app.muukii.tone.transcription",
  ]),
  "CFBundleDisplayName": "Tone",
  "ITSAppUsesNonExemptEncryption": false,
  "LSApplicationCategoryType": "public.app-category.education",
  "NSMicrophoneUsageDescription":
    "To record your voice and play it back for pronunciation practice.",
  "NSSpeechRecognitionUsageDescription":
    "To transcribe imported audio into synchronized subtitle chunks on device.",
  "NSSupportsLiveActivities": true,
  "UIApplicationSceneManifest": .dictionary([
    "UIApplicationSupportsMultipleScenes": true,
    "UISceneConfigurations": .dictionary([:]),
  ]),
  "UIBackgroundModes": .array(["audio", "processing"]),
  "UILaunchScreen": .dictionary([:]),
]) { _, new in new })

let project = Project(
  name: "Tone",
  organizationName: AppConstants.organizationName,
  options: .options(
    developmentRegion: "en",
    disableBundleAccessors: true,
    disableSynthesizedResourceAccessors: true,
    textSettings: .textSettings(
      usesTabs: false,
      indentWidth: 2,
      tabWidth: 2,
      wrapsLines: true
    ),
    xcodeProjectName: "Tone"
  ),
  settings: .settings(
    base: .base.merging([
      "CURRENT_PROJECT_VERSION": "1",
      "MARKETING_VERSION": "$(APP_SHORT_VERSION)",
    ]),
    configurations: [
      .debug(name: "Debug", xcconfig: "xcconfigs/Project.xcconfig"),
      .release(name: "Release", xcconfig: "xcconfigs/Project.xcconfig"),
    ]
  ),
  targets: [
    .target(
      name: "Tone",
      destinations: [.iPhone],
      product: .app,
      bundleId: "app.muukii.tone",
      deploymentTargets: .app,
      infoPlist: toneInfoPlist,
      buildableFolders: ["ShadowingPlayer"],
      entitlements: .dictionary([
        "com.apple.developer.icloud-container-identifiers": ["iCloud.app.muukii.tone"],
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.security.application-groups": ["group.app.muukii.tone"],
      ]),
      dependencies: [
        .sdk(name: "CloudKit", type: .framework),

        .target(name: "ActivityContent"),
        .target(name: "AppService"),
        .target(name: "LiveActivity"),
        .target(name: "UIComponents"),

        .external(name: "Alamofire"),
        .external(name: "Algorithms"),
        .external(name: "CollectionView"),
        .external(name: "ConcurrencyTaskManager"),
        .external(name: "DSWaveformImage"),
        .external(name: "DSWaveformImageViews"),
        .external(name: "DynamicList"),
        .external(name: "HexColorMacro"),
        .external(name: "ObjectEdge"),
        .external(name: "StateGraph"),
        .external(name: "SwiftSubtitles"),
        .external(name: "SwiftUIIntrospect"),
        .external(name: "SwiftUIPersistentControl"),
        .external(name: "SwiftUIRingSlider"),
        .external(name: "SwiftUISupport"),
        .external(name: "SwiftUISupportLayout"),
        .external(name: "Wrap"),
        .external(name: "YouTubeKit"),
      ],
      settings: .settings(
        base: .appTarget.merging([
          "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
          "DEVELOPMENT_ASSET_PATHS": #""ShadowingPlayer/Preview Content""#,
          "OTHER_LDFLAGS": "$(inherited) -all_load",
          "SWIFT_DEFAULT_ACTOR_ISOLATION": "",
          "TARGETED_DEVICE_FAMILY": "1",
        ]),
        configurations: [
          .debug(name: "Debug", xcconfig: "xcconfigs/Project.xcconfig"),
          .release(name: "Release", xcconfig: "xcconfigs/Project.xcconfig"),
        ]
      )
    ),

    .target(
      name: "LiveActivity",
      destinations: .iOS,
      product: .appExtension,
      bundleId: "app.muukii.tone.LiveActivity",
      deploymentTargets: .app,
      infoPlist: .dictionary(toneVersionInfoPlistKeys.merging([
        "CFBundleDisplayName": "Tone Widget",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleName": "$(PRODUCT_NAME)",
        "NSExtension": .dictionary([
          "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
        ]),
      ]) { _, new in new }),
      buildableFolders: ["Sources/LiveActivity"],
      entitlements: .dictionary([
        "com.apple.security.application-groups": ["group.app.muukii.tone"],
      ]),
      dependencies: [
        .target(name: "ActivityContent"),
      ],
      settings: .settings(base: .base.merging([
        "APPLICATION_EXTENSION_API_ONLY": "YES",
      ]))
    ),

    .target(
      name: "AppService",
      destinations: [.iPhone],
      product: .staticLibrary,
      bundleId: "app.muukii.tone.AppService",
      deploymentTargets: .app,
      buildableFolders: ["Sources/AppService"],
      dependencies: [
        .target(name: "ActivityContent"),
        .external(name: "Alamofire"),
        .external(name: "ConcurrencyTaskManager"),
        .external(name: "StateGraph"),
        .external(name: "SwiftSubtitles"),
        .external(name: "Wrap"),
      ],
      settings: .settings(base: .frameworkTarget)
    ),

    .target(
      name: "ActivityContent",
      destinations: [.iPhone],
      product: .framework,
      bundleId: "app.muukii.tone.ActivityContent",
      deploymentTargets: .app,
      infoPlist: .default,
      buildableFolders: ["Sources/ActivityContent"],
      dependencies: [],
      settings: .settings(base: .frameworkTarget)
    ),

    .target(
      name: "UIComponents",
      destinations: [.iPhone],
      product: .framework,
      bundleId: "app.muukii.tone.UIComponents",
      deploymentTargets: .app,
      infoPlist: .default,
      buildableFolders: ["Sources/UIComponents"],
      dependencies: [
        .external(name: "SwiftUISupport"),
        .external(name: "SwiftUISupportLayout"),
      ],
      settings: .settings(base: .frameworkTarget)
    ),
  ],
  schemes: [
    .scheme(
      name: "Tone",
      shared: true,
      hidden: false,
      buildAction: .buildAction(targets: ["Tone"]),
      testAction: nil,
      runAction: .runAction(configuration: "Debug", attachDebugger: true),
      archiveAction: .archiveAction(configuration: "Release"),
      profileAction: .profileAction(configuration: "Debug"),
      analyzeAction: nil
    ),
  ]
)
