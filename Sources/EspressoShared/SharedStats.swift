import Foundation

/// Compact widget-friendly snapshot of Espresso's state. Written by
/// the host on every state change + tick, read by the widget's
/// timeline provider for the next refresh.
///
/// Kept deliberately small — only what the widget actually renders.
/// Schema additions are cheap (Codable round-trips + decode defaults
/// keep older readers working), but every byte here gets serialised
/// twice a second so don't pile on.
public struct SharedStats: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public var version: Int

    /// True when keep-awake is currently engaged.
    public var active: Bool
    /// Human-readable mode label ("Display + System", "Display only",
    /// "System only"). The host renders the enum into a string so the
    /// widget doesn't need to know about `AwakeMode`.
    public var modeLabel: String
    /// Human-readable remaining time ("1h 23m" / "45s") or empty if
    /// the preset is indefinite or Espresso is off.
    public var remaining: String
    /// Human-readable elapsed time since this session started ("12m
    /// 4s"). Empty when Espresso is off.
    public var elapsed: String
    /// Mouse-jiggle currently running.
    public var jiggleOn: Bool
    /// Clamshell mode (laptop lid closed, keep going).
    public var clamshellOn: Bool
    /// Snapshot time — widget uses this to badge a "stale" state if
    /// the host hasn't ticked in a while.
    public var sampledAt: Date

    public init(
        version: Int = SharedStats.currentVersion,
        active: Bool = false,
        modeLabel: String = "",
        remaining: String = "",
        elapsed: String = "",
        jiggleOn: Bool = false,
        clamshellOn: Bool = false,
        sampledAt: Date = .distantPast
    ) {
        self.version = version
        self.active = active
        self.modeLabel = modeLabel
        self.remaining = remaining
        self.elapsed = elapsed
        self.jiggleOn = jiggleOn
        self.clamshellOn = clamshellOn
        self.sampledAt = sampledAt
    }

    /// Placeholder for the gallery preview + first launch before any
    /// snapshot lands on disk.
    public static let placeholder = SharedStats(
        active: false,
        modeLabel: "Display + System",
        remaining: "",
        elapsed: "",
        jiggleOn: false,
        clamshellOn: false,
        sampledAt: .distantPast
    )
}
