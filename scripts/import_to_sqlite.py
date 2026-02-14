#!/usr/bin/env python3
"""
Import chunks with embeddings into SQLite database for the Swift app.
Reads chunks_with_embeddings.json and creates rag.db.
"""

import json
import sqlite3
import struct
import os
from pathlib import Path

DATA_DIR = Path(__file__).parent.parent / "data"
CHUNKS_FILE = DATA_DIR / "chunks_with_embeddings.json"
STYLES_DIR = DATA_DIR / "styles"

# Output to Application Support directory
APP_SUPPORT = Path.home() / "Library" / "Application Support" / "MEI"
RAG_DB_PATH = APP_SUPPORT / "rag.db"


def float_list_to_blob(floats):
    """Convert list of floats to binary blob for SQLite."""
    return struct.pack(f"{len(floats)}f", *floats)


def main():
    if not CHUNKS_FILE.exists():
        print(f"Error: {CHUNKS_FILE} not found. Run generate_embeddings.py first.")
        return

    with open(CHUNKS_FILE) as f:
        chunks = json.load(f)

    print(f"Loaded {len(chunks)} chunks")

    # Create output directory
    APP_SUPPORT.mkdir(parents=True, exist_ok=True)

    # Remove old database if exists
    if RAG_DB_PATH.exists():
        os.remove(RAG_DB_PATH)

    conn = sqlite3.connect(str(RAG_DB_PATH))
    cursor = conn.cursor()

    # Create tables
    cursor.executescript("""
        CREATE TABLE chunks (
            id TEXT PRIMARY KEY,
            contact TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            message_count INTEGER,
            is_group_chat BOOLEAN DEFAULT FALSE,
            chunk_text TEXT NOT NULL,
            topics TEXT,
            embedding BLOB NOT NULL
        );

        CREATE INDEX idx_chunks_contact ON chunks(contact);
        CREATE INDEX idx_chunks_timestamp ON chunks(timestamp);

        CREATE TABLE agent_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            contact TEXT NOT NULL,
            incoming_text TEXT NOT NULL,
            generated_text TEXT NOT NULL,
            confidence REAL,
            was_sent BOOLEAN,
            was_shadow BOOLEAN DEFAULT FALSE,
            reply_delay_seconds REAL,
            rag_chunks_used TEXT,
            user_feedback TEXT
        );

        CREATE TABLE sync_state (
            key TEXT PRIMARY KEY,
            value TEXT
        );

        INSERT INTO sync_state VALUES ('last_processed_rowid', '0');
    """)

    # Insert chunks
    inserted = 0
    for chunk in chunks:
        embedding = chunk.get("embedding")
        if not embedding:
            continue

        embedding_blob = float_list_to_blob(embedding)

        cursor.execute(
            """INSERT OR REPLACE INTO chunks
               (id, contact, timestamp, message_count, is_group_chat, chunk_text, topics, embedding)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                chunk["id"],
                chunk["contact"],
                chunk.get("first_date", ""),
                chunk.get("message_count", 0),
                chunk.get("is_group", False),
                chunk["text"],
                json.dumps([]),  # topics - could be extracted later
                embedding_blob,
            ),
        )
        inserted += 1

    conn.commit()

    # Copy style profiles
    styles_dest = APP_SUPPORT / "styles"
    styles_dest.mkdir(parents=True, exist_ok=True)

    if STYLES_DIR.exists():
        import shutil
        for f in STYLES_DIR.glob("*.json"):
            shutil.copy2(f, styles_dest / f.name)
        print(f"Copied {len(list(STYLES_DIR.glob('*.json')))} style profiles to {styles_dest}")

    # Stats
    cursor.execute("SELECT COUNT(*) FROM chunks")
    count = cursor.fetchone()[0]

    conn.close()

    db_size = RAG_DB_PATH.stat().st_size / 1024 / 1024

    print(f"\nImported {inserted} chunks into {RAG_DB_PATH}")
    print(f"Database: {count} chunks, {db_size:.1f} MB")
    print(f"\nSetup complete! The MEI app can now use:")
    print(f"  RAG DB: {RAG_DB_PATH}")
    print(f"  Styles: {styles_dest}")


if __name__ == "__main__":
    main()
