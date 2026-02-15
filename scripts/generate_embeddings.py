#!/usr/bin/env python3
"""
Chunk conversations and generate embeddings via Gemini Embedding API.
Reads conversations.json, outputs chunks with embeddings.
"""

import json
import os
import time
import hashlib
from pathlib import Path

try:
    from google import genai
    from google.genai import types
except ImportError:
    print("Install google-genai: pip install google-genai")
    exit(1)

DATA_DIR = Path(__file__).parent.parent / "data"
CONVERSATIONS_FILE = DATA_DIR / "conversations.json"
CHUNKS_FILE = DATA_DIR / "chunks_with_embeddings.json"

# Configure - set your API key (or GEMINI_API_KEY / GOOGLE_API_KEY env var)
API_KEY = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""
if not API_KEY:
    print("Set GEMINI_API_KEY environment variable")
    print("  export GEMINI_API_KEY=your_key_here")
    exit(1)

client = genai.Client(api_key=API_KEY)

CHUNK_SIZE = 10  # messages per chunk
CHUNK_OVERLAP = 3  # overlap between chunks


def chunk_conversation(messages, chunk_size=CHUNK_SIZE, overlap=CHUNK_OVERLAP):
    """Split a conversation into overlapping chunks."""
    chunks = []
    for i in range(0, len(messages), chunk_size - overlap):
        chunk_msgs = messages[i:i + chunk_size]
        if len(chunk_msgs) < 3:  # skip very short chunks
            continue

        # Format as readable text
        lines = []
        for msg in chunk_msgs:
            sender = "Matthew" if msg["is_from_me"] else "Them"
            lines.append(f"{sender}: {msg['text']}")

        chunk_text = "\n".join(lines)
        chunk_id = hashlib.md5(chunk_text.encode()).hexdigest()[:12]

        chunks.append({
            "id": chunk_id,
            "text": chunk_text,
            "message_count": len(chunk_msgs),
            "first_date": chunk_msgs[0].get("date", ""),
            "last_date": chunk_msgs[-1].get("date", ""),
        })

    return chunks


def embed_text(text, retries=3):
    """Generate embedding for text using Gemini Embedding API."""
    for attempt in range(retries):
        try:
            response = client.models.embed_content(
                model="gemini-embedding-001",
                contents=text,
                config=types.EmbedContentConfig(output_dimensionality=768),
            )
            if response.embeddings:
                return list(response.embeddings[0].values)
            return None
        except Exception as e:
            if attempt < retries - 1:
                wait = 2 ** attempt
                print(f"  Retry in {wait}s: {e}")
                time.sleep(wait)
            else:
                print(f"  Failed to embed: {e}")
                return None


def main():
    if not CONVERSATIONS_FILE.exists():
        print(f"Error: {CONVERSATIONS_FILE} not found. Run extract_history.py first.")
        return

    with open(CONVERSATIONS_FILE) as f:
        all_chats = json.load(f)

    all_chunks = []
    total_embedded = 0

    for chat_id, chat_data in all_chats.items():
        if chat_data.get("is_group"):
            continue

        contact_id = chat_id.split(";")[-1]
        display_name = chat_data.get("display_name", contact_id)

        all_msgs = []
        for convo in chat_data.get("conversations", []):
            all_msgs.extend(convo)

        if len(all_msgs) < 10:
            continue

        # Chunk all messages for this contact
        for convo in chat_data.get("conversations", []):
            chunks = chunk_conversation(convo)
            for chunk in chunks:
                chunk["contact"] = contact_id
                chunk["contact_name"] = display_name
                chunk["is_group"] = False
                all_chunks.append(chunk)

    print(f"Generated {len(all_chunks)} chunks from {len(all_chats)} chats")
    print("Generating embeddings (this may take a while)...")

    # Embed in batches with rate limiting
    for i, chunk in enumerate(all_chunks):
        embedding = embed_text(chunk["text"])
        if embedding:
            chunk["embedding"] = embedding
            total_embedded += 1

        if (i + 1) % 50 == 0:
            print(f"  Embedded {i + 1}/{len(all_chunks)} chunks...")

        # Rate limiting: ~1500 RPM for free tier
        time.sleep(0.05)

    # Remove chunks without embeddings
    all_chunks = [c for c in all_chunks if "embedding" in c]

    # Save
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with open(CHUNKS_FILE, "w") as f:
        json.dump(all_chunks, f)

    print(f"\nEmbedded {total_embedded} chunks")
    print(f"Output: {CHUNKS_FILE}")
    print(f"File size: {CHUNKS_FILE.stat().st_size / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
