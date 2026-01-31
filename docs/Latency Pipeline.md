# Latency Pipeline

This document visualizes all steps in the transcription pipeline that can add latency. **Update this when adding new features.**

---

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           LATENCY PIPELINE                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  🎤 RECORDING                                                               │
│  └── User holds hotkey → Audio captured → File saved                        │
│      Typical: ~instant (user-controlled)                                    │
│                                                                             │
│  ──────────────────────────────────────────────────────────────────────     │
│                                                                             │
│  📝 TRANSCRIPTION                     ⏱️ 0.2s - 5s                          │
│  ├── Apple Speech (streaming)         ~0.2s - 1s                            │
│  └── Whisper (local)                  ~0.3s - 2s (English-only model)       │
│      └── Audio decode                 ~0.05s                                │
│      └── Model inference              ~0.3s - 2s                            │
│                                                                             │
│  ──────────────────────────────────────────────────────────────────────     │
│                                                                             │
│  🤖 LLM PROCESSING (Smart Flow)       ⏱️ 0.1s - 10s                         │
│  ├── Groq (Cloud)                     ~0.1s - 0.3s ✅ Fastest               │
│  ├── OpenAI (Cloud)                   ~0.5s - 2s                            │
│  └── Ollama (Local)                   ~2s - 10s (cold start: +5s)           │
│  └── Includes: Dictionary context-aware replacements (zero extra latency)  │
│                                                                             │
│  ──────────────────────────────────────────────────────────────────────     │
│                                                                             │
│  📚 DICTIONARY REPLACEMENT            ⏱️ <0.01s                             │
│  └── Regex matching on learned words                                        │
│  └── Context matching (semantic)      ~TBD (pending implementation)         │
│                                                                             │
│  ──────────────────────────────────────────────────────────────────────     │
│                                                                             │
│  ⌨️ TEXT INJECTION                    ⏱️ ~0.1s                              │
│  └── Clipboard + Cmd+V paste                                                │
│                                                                             │
│  ──────────────────────────────────────────────────────────────────────     │
│                                                                             │
│  👁️ CORRECTION SESSION (async)        ⏱️ 3-20s (background)                 │
│  └── Idle timeout                     3s                                    │
│  └── Hard stop                        20s                                   │
│  └── Does NOT block pipeline                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Typical End-to-End Latency

| Configuration                             | Transcription | LLM   | Total     |
| ----------------------------------------- | ------------- | ----- | --------- |
| **Fastest** (Apple Speech + Groq)         | 0.2s          | 0.15s | **~0.5s** |
| **Local Fast** (Whisper EN + skip LLM)    | 0.3s          | 0s    | **~0.5s** |
| **Balanced** (Whisper EN + Groq)          | 0.5s          | 0.2s  | **~1s**   |
| **Full Local** (Whisper EN + Ollama warm) | 0.5s          | 2s    | **~3s**   |
| **Slow** (Whisper EN + Ollama cold)       | 0.5s          | 10s   | **~11s**  |

---

## Logging

Timing logs are written to: `~/Desktop/wispr_timing.log`

Sample output:

```
⏱️ Transcription: 0.32s
⏱️ LLM Processing: 2.11s [Provider: Ollama (Local)]
📚 Session ended. Injected: '...' | Corrected: '...'
```

---

## Known Latency Issues

| Issue                   | Cause                           | Fix                                       |
| ----------------------- | ------------------------------- | ----------------------------------------- |
| Ollama cold start       | Model loads into GPU            | Keep Ollama warm with frequent use        |
| Multilingual Whisper    | Slower than English-only        | Use `ggml-*.en.bin` models                |
| App Nap (Finder launch) | macOS throttles background apps | `NSAppSleepDisabled = true` in Info.plist |

---

## Last Updated

2026-01-29
