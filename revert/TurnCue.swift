import AudioToolbox

/// A short audible cue at the last distance rung, for the rides where the
/// rider has muted navigation voice. It is deliberately quiet and short: the
/// voice already covers the audible case, so this only fills the silence.
nonisolated enum TurnCue {
    static func approach() {
        AudioServicesPlaySystemSound(1104)
    }
}
