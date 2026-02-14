#!/usr/bin/env python3
"""
Extract and clean iMessage chat history from chat.db.
Outputs structured conversation data as JSON.
"""

import sqlite3
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from collections import defaultdict

# macOS Messages chat.db path
CHAT_DB = os.path.expanduser("~/Library/Messages/chat.db")
OUTPUT_DIR = Path(__file__).parent.parent / "data"
OUTPUT_FILE = OUTPUT_DIR / "conversations.json"


def cocoa_to_datetime(cocoa_timestamp):
    """Convert macOS Core Data timestamp (nanoseconds since 2001-01-01) to datetime."""
    if cocoa_timestamp is None or cocoa_timestamp == 0:
        return None
    # Reference date: 2001-01-01 00:00:00 UTC
    seconds = cocoa_timestamp / 1_000_000_000
    reference = datetime(2001, 1, 1, tzinfo=timezone.utc)
    try:
        return datetime.fromtimestamp(reference.timestamp() + seconds, tz=timezone.utc)
    except (OSError, ValueError):
        return None


def extract_messages(db_path):
    """Extract all messages from chat.db grouped by chat."""
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row

    query = """
        SELECT
            m.ROWID,
            m.text,
            m.is_from_me,
            m.date,
            m.cache_has_attachments,
            c.chat_identifier,
            c.display_name,
            c.style,
            h.id as handle_id
        FROM message m
        JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        JOIN chat c ON cmj.chat_id = c.ROWID
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        WHERE m.text IS NOT NULL AND m.text != ''
        ORDER BY m.date ASC
    """

    cursor = conn.execute(query)
    chats = defaultdict(list)

    for row in cursor:
        dt = cocoa_to_datetime(row["date"])
        if dt is None:
            continue

        msg = {
            "rowid": row["ROWID"],
            "text": row["text"].strip(),
            "is_from_me": bool(row["is_from_me"]),
            "date": dt.isoformat(),
            "chat_identifier": row["chat_identifier"],
            "display_name": row["display_name"] or "",
            "is_group": row["style"] == 43,
            "handle_id": row["handle_id"] or "",
            "has_attachment": bool(row["cache_has_attachments"]),
        }

        chats[row["chat_identifier"]].append(msg)

    conn.close()
    return dict(chats)


def split_into_conversations(messages, gap_minutes=60):
    """Split a list of messages into conversations based on time gaps."""
    if not messages:
        return []

    conversations = []
    current = [messages[0]]

    for msg in messages[1:]:
        prev_time = datetime.fromisoformat(current[-1]["date"])
        curr_time = datetime.fromisoformat(msg["date"])
        gap = (curr_time - prev_time).total_seconds() / 60

        if gap > gap_minutes:
            conversations.append(current)
            current = [msg]
        else:
            current.append(msg)

    if current:
        conversations.append(current)

    return conversations


def main():
    if not os.path.exists(CHAT_DB):
        print(f"Error: chat.db not found at {CHAT_DB}")
        print("Make sure you've granted Full Disk Access to your terminal.")
        return

    print(f"Reading messages from {CHAT_DB}...")
    chats = extract_messages(CHAT_DB)
    print(f"Found {len(chats)} chats")

    # Process into conversations
    all_conversations = {}
    total_msgs = 0
    total_convos = 0

    for chat_id, messages in chats.items():
        conversations = split_into_conversations(messages)
        all_conversations[chat_id] = {
            "chat_identifier": chat_id,
            "display_name": messages[0]["display_name"] if messages else "",
            "is_group": messages[0]["is_group"] if messages else False,
            "total_messages": len(messages),
            "conversations": conversations,
        }
        total_msgs += len(messages)
        total_convos += len(conversations)

    # Write output
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_FILE, "w") as f:
        json.dump(all_conversations, f, indent=2, default=str)

    print(f"Extracted {total_msgs} messages in {total_convos} conversations")
    print(f"Output: {OUTPUT_FILE}")

    # Print top contacts by message count
    print("\nTop contacts by message count:")
    sorted_chats = sorted(chats.items(), key=lambda x: len(x[1]), reverse=True)
    for chat_id, msgs in sorted_chats[:15]:
        name = msgs[0]["display_name"] or chat_id.split(";")[-1]
        my_msgs = sum(1 for m in msgs if m["is_from_me"])
        their_msgs = len(msgs) - my_msgs
        print(f"  {name}: {len(msgs)} total ({my_msgs} sent, {their_msgs} received)")


if __name__ == "__main__":
    main()
