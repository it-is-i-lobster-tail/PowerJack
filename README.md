# PowerJack

A lifting app for people who already know their way around the gym and want every session to count toward building muscle.

**Simple.** Open it, see today's workout, and lift. Nothing gets between you and the next set.

**Focused on your goals.** Your program is built around what you're training for, so every workout has a purpose.

**Personal and private.** Your training is yours. No accounts, no ads, no tracking. See the [privacy policy](PRIVACY.md).

**Progresses with you.** As you get stronger, your program moves with you, and it adapts when life or recovery calls for it.

**Made your way.** Shape your programs, templates and exercises until they fit how you like to train.

**Free and open source.** PowerJack is free, and the code is here under the [MIT License](LICENSE).

## Building

PowerJack is a native SwiftUI app for iPhone and Apple Watch with no third-party dependencies.

1. Open `PowerJack/PowerJack.xcodeproj` in Xcode 26 or later.
2. Select the `PowerJack` scheme and an iPhone simulator (iOS 26.2 or later).
3. Build and run with ⌘R. Run the tests with ⌘U.

For the watch app, select the `PowerJackWatch` scheme and a paired Apple Watch simulator. Simulators aren't signed in to iCloud, so turn on the scheme's `-demoProgram hypertrophy` launch argument (or use `strength` or `powerjack`) to start a program on the watch itself.

## Contact

Questions, ideas or bugs: [powerjack@brendonstanley.com](mailto:powerjack@brendonstanley.com)
