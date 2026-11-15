# Platform implementation and distribution

The shared product is an offline Bopomofo input method with Simplified and Traditional Chinese output, local selection memory, a personal lexicon and association ranking.

| Platform | Current state | Native integration |
| --- | --- | --- |
| macOS | 0.2 downloadable Apple Silicon installer preview; embedded payload signature checked; Developer ID/notarization pending | InputMethodKit and AppKit |
| Windows | 0.3 native service and dictionary manager verified on x64/x86; installer and uninstall preservation checks passed | Text Services Framework |
| iOS | Native app and keyboard built; iPhone/iPad component tests and unsigned device archive verified; signing and store release pending | Custom Keyboard extension and a containing app |

## Windows

Implement a TSF text service with explicit composition and candidate UI. Keep dictionaries readable under the platform's app-container rules, and keep personal learning private. Register language profiles through the documented TSF APIs. Do not change the user's default keyboard through registry edits. See [Microsoft IME requirements](https://learn.microsoft.com/en-us/windows/apps/develop/input/input-method-editor-requirements) and [text-service registration](https://learn.microsoft.com/en-us/windows/win32/tsf/text-service-registration).

## iOS

Use a keyboard extension that works without Full Access and without network access. The containing app manages the shared personal lexicon; the keyboard reads that lexicon and stores learning in its own writable sandbox. Shared-container access and data controls must follow [Apple's keyboard access rules](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard). Provide a next-keyboard control and follow [App Review keyboard requirements](https://developer.apple.com/app-store/review/guidelines/#extensions).

## Public releases

Keep source availability, a test build, signed distribution and a public store listing distinct. A local ad hoc Mac build is not a notarized release. Windows installation and input tests, Apple signing, notarization and App Store review remain separate acceptance steps. Do not mark a platform released until its downloadable build and installation path are verified.
