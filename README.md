# Ask for Mac

Ask your Mac a question in your own words. Get the answer, and the file it came from. Nothing leaves the Mac.

"how much was the lease deposit" → *The security deposit on the Woodland Ave lease is $2,400, due at signing [1].* with the lease one click away.

## Download

**[Download Ask-for-Mac-0.6.0.dmg](https://github.com/keithadler/askmac/releases/latest/download/Ask-for-Mac-0.6.0.dmg)** (macOS 14 or later, Apple Silicon and Intel; written answers need macOS 26 with Apple Intelligence)

Open the DMG, drag the app to Applications, open it. The first time, macOS says the app is from an unidentified developer: right-click the app, choose Open, then Open again. That is once. Nothing else to set up.

![Answer](docs/screenshots/answer.png)

## How it works

1. **Find.** Your Mac already keeps a full-text index of every file and mail message: Spotlight. Ask for Mac asks it for files containing your words, within the dates you named.
2. **Read.** Those files are read on the Mac: PDF, Word, Excel, PowerPoint, RTF, HTML, text, Markdown, CSV and Mail messages. When a question asks for a screenshot or photo, images are read with on-device text recognition; when it mentions notes, Apple Notes are read through the Notes app.
3. **Rank.** Each file becomes passages, scored on the words they contain and on meaning, using the Mac's own word embeddings. No file may take more than three places.
4. **Answer.** On macOS 26 with Apple Intelligence, Apple's on-device model writes two or three sentences from those passages with numbered citations, and says plainly when the files do not answer. Anywhere else, the answer is the best sentence quoted from the top file.

Every answer lists its sources. An answer you cannot check is not an answer. While it works, the window says what it is doing ("Reading 12 files…") and the answer streams in as Apple's model writes it. ⌥ Space brings the window forward from anywhere. Follow-ups work: after "lease deposit", "and when is rent due" keeps looking at the lease.

## What it does not do

- It does not upload anything, anywhere, ever. No account, no server, no Private Cloud Compute.
- It does not build a second index of your files. Spotlight's is the only one.
- It does not read Numbers, Pages or Keynote yet; Apple keeps their text in a format nothing else can read. Images are read only when a question asks for a screenshot or photo, because recognising text in every picture for every question would be slow.
- It does not answer from general knowledge. If it is not in your files, it says so, and lists the closest files so you can look yourself.
- Folders you do not want searched, a folder of source repositories inside Downloads say, can be skipped in Settings or with `askmac skip add <path>`.

## Command line

```
ln -s "/Applications/Ask for Mac.app/Contents/MacOS/AskMac" /usr/local/bin/askmac
askmac "lease deposit last week"
askmac "dentist invoice crown" --json
askmac "tax return 2025 total" --quote
askmac status
```

Exit 0 when answered, 1 when nothing was found.

## Building

```
./build-app.sh --install      # universal build, ad-hoc signed, into /Applications
askmac selftest               # tests without Xcode, against a temporary folder of files
swift test                    # the same tests through XCTest
tests/integration.sh          # the command line end to end
```

MIT licensed. See [PRIVACY.md](PRIVACY.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
