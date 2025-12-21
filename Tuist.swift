import ProjectDescription

let tuist = Tuist(
  fullHandle: "muukii/YouTubeSubtitle",
  project: .tuist(
    generationOptions: .options(
      enforceExplicitDependencies: true
    )
  )
)
