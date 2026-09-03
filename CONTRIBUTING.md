# Contributing

Thank you. The bar here is the same as for the other apps in the family: one thing, plainly explained, and nothing leaves the Mac.

- Build with `./build-app.sh`; the Command Line Tools are enough. Written answers need the macOS 26 SDK, which the build uses when present and weak-links so the app still runs on macOS 14 and 15.
- Run `askmac selftest` before a pull request. Tests build a temporary folder of files and never read your real ones.
- A new file type goes in `Extract.swift` with a test that reads a synthetic file of that type.
- Anything that would send data off the Mac will not be merged.

MIT licensed; contributions are accepted under the same license.
