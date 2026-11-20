import AVFAudio

/// Audio session configuration runs off the main thread.
///
/// `AVAudioSession` activation can block while the system re-routes audio, and
/// Xcode flags the synchronous calls on the main thread as a UI hang risk
/// ("This method can lead to UI unresponsiveness…"). The serial queue keeps
/// category, preferred input and activation in order while the main thread
/// stays free.
enum AudioSessionWork {
    private static let queue = DispatchQueue(
        label: "com.davidmolina.Revert.audioSession",
        qos: .userInitiated
    )

    /// Fire-and-forget configuration. Order is preserved, completion is not.
    static func perform(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Await configuration when the caller cannot proceed until it lands —
    /// the recogniser needs its category and input before the tap is installed.
    static func performAndWait(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                work()
                continuation.resume()
            }
        }
    }
}
