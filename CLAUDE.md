# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MEI is a macOS menu bar application that autonomously responds to iMessage conversations using AI. It reads from the macOS Messages database (`chat.db`), generates responses via Google Gemini API that match the user's communication style (per-contact style profiles + RAG), and sends them via AppleScript.

**Tech stack:** Swift, SwiftUI, macOS-only, no external package dependencies. Uses native `SQLite3`, `Security` (Keychain), `UserNotifications`, and AppleScript for Messages integration.

## Build Commands

```bash
xcodebuild -scheme MEI build                    # Build
xcodebuild -scheme MEI run                      # Run
```

The Xcode project is at `../MEI.xcodeproj`. No test target exists yet.

## Architecture

### Core Loop (`Agent/`)
`AgentLoop` polls `chat.db` every 2 seconds. For each new incoming message:
1. `SafetyChecks` validates (skip own messages, group chats, kill words, active hours, typing detection)
2. `RAGDatabase` retrieves similar past conversation chunks via cosine similarity
3. `StyleProfile` loads contact-specific communication patterns (JSON files in App Support)
4. `PromptBuilder` constructs the full prompt with system instructions, RAG context, style profile, and conversation history
5. `GeminiClient` generates a response; response is parsed into `AgentResponse` (confidence score + multi-message split on `|||`)
6. `BehaviorEngine` simulates human reply delays and multi-message bursts
7. `MessageSender` sends via AppleScript
8. `AgentLogDatabase` logs the exchange

### Operational Modes
- **Active** — sends responses autonomously
- **Shadow** — generates and logs but never sends (for testing)
- **Paused** — agent disabled
- **Killed** — stopped by kill word detection

### State Management
`AppState` is the central `@Observable` object on `@MainActor`. It holds agent mode, contact configs, settings (confidence threshold, active hours, delays, kill words, restricted topics). The agent loop and all views observe it reactively.

### Concurrency Model
- `MessageReader`, `GeminiClient`, `GeminiEmbedding` are Swift **actors** for thread safety
- `AppState` and `AgentLoop` are `@MainActor`
- Uses Swift structured concurrency (`async/await`, `Task`)

### Data Storage
All databases live in `~/Library/Application Support/MEI/`:
- `rag.db` — conversation chunks with embeddings for retrieval
- `agent_log.db` — logged exchanges (incoming text, generated text, confidence, delay, RAG chunks used)
- `styles/` — per-contact JSON style profiles

### Data Preparation Pipeline (`scripts/`)
Python scripts run manually during setup to populate the RAG database:
1. `extract_history.py` — reads `~/Library/Messages/chat.db`
2. `extract_style.py` — generates per-contact style profiles
3. `generate_embeddings.py` — creates embeddings via Gemini API
4. `import_to_sqlite.py` — imports chunks into `rag.db`

### UI Structure
Menu bar app with a popover for quick status and a dashboard window with 4 tabs: Live Feed, Contacts, Stats, Settings. `OnboardingView` handles first-launch setup including Gemini API key entry (stored in Keychain).

## Key Conventions

- Bundle ID: `com.matthewpetersen.MEI`
- RAG uses brute-force cosine similarity (no vector DB extension)
- Gemini model: `gemini-2.5-flash` for generation, `gemini-embedding-001` for embeddings
- Confidence threshold default: 0.75 (configurable 0.5–1.0)
- Per-contact control: active, shadow-only, whitelist, blacklist modes
- Message history context: last 20 messages per conversation
