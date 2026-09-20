import Testing

// Why this exists instead of a plain `.testTarget`:
//
// SwiftPM builds macOS test targets as loadable .xctest BUNDLES, which are run
// by a harness that ships with Xcode. On a Command Line Tools-only machine the
// bundle builds and links, `swift test` prints "Build complete!", and then
// executes ZERO tests while exiting 0. A silent false green is worse than no
// tests at all - this suite contains a canary that asserts an auth token never
// leaks, and that check passing vacuously would be actively misleading.
//
// So the suite is an ordinary executable that invokes swift-testing's own
// SwiftPM entry point and exits with its status. `swift run VibraTests`.
//
// RISK, accepted deliberately: __swiftPMEntryPoint is the integration symbol
// SwiftPM itself calls, and its double-underscore name marks it as not a
// stable public API. It is present in the shipped Testing.swiftinterface for
// this toolchain. If a future toolchain removes it, this target fails to
// COMPILE - loudly - rather than silently skipping tests. That failure mode is
// the reason this is acceptable.
await Testing.__swiftPMEntryPoint() as Never
