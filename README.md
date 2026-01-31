# Wispr Clone (macOS)

A high-performance, local-first dictation app for macOS that lives in your menu bar.

## Features

- **Global Hotkey:** Hold `Option+Space` to record anywhere.
- **Instant Transcription:** Uses on-device Whisper models (Base, Small, Medium) or Apple Speech.
- **Smart Flow:** Optional Cloud AI post-processing (OpenAI or Groq) to format text (e.g., bullet points, email cleanup).
- **Custom Vocabulary:** Add personal words (names, acronyms, jargon) to improve recognition accuracy.
- **Auto-Learn Dictionary:** Automatically learns from your corrections and applies them to future dictations.
- **Optimized Whisper Engine:** Local transcription optimized with 8-thread inference for <2s latency.
- **Latency Speedometer:** Real-time performance tracking in the menu bar.
- **Zero-Latency Mode:** Optimized for <1.5s turnaround with Groq.
- **Stealth Paste:** Keeps your clipboard history clear by using transient metadata.
- **Global 10s Timeout:** All processing stacks timeout after 10 seconds to prevent hangs.

## Installation

See [Deployment Guide](docs/deployment.md) for detailed installation instructions on other Macs.

## Development

### Prerequisites

- macOS 14+ (Sonoma)
- Xcode 15+ (for building)

### Build

Run the build script to create a standalone app bundle:

```bash
./scripts/build_app.sh
```

### Release

To create a portable zip for distribution:

```bash
./scripts/release.sh
```
