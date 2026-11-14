import Testing
@testable import InputSourceHelper

@Suite("Installation activation")
struct ActivationTests {
    @Test("An enabled child does not make a disabled input method ready", arguments: [
        (false, true, true),
        (false, false, true),
        (true, false, true),
        (true, true, false),
    ])
    func requiresConfirmation(parent: Bool, mode: Bool, expected: Bool) {
        #expect(InputSourceHelper.requiresUserActivation(parentEnabled: parent, hasEnabledMode: mode) == expected)
    }
}
