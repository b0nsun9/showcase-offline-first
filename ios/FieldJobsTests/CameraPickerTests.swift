@testable import FieldJobs
import Testing
import UIKit

@MainActor @Suite(.timeLimit(.minutes(1))) struct CameraPickerTests {
    /// The tests run on the simulator, which reports a camera but has no picture to take.
    @Test func simulatorPicksFromTheLibrary() {
        #expect(CameraPicker.sourceType == .photoLibrary)
    }
}
