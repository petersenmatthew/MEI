#!/usr/bin/env python3
"""
Analyze chat history to generate per-contact style profiles.
Reads conversations.json from extract_history.py output.
"""

import json
import os
import re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

import nltk
from nltk.tokenize import word_tokenize, sent_tokenize
from nltk.corpus import stopwords
from nltk.sentiment.vader import SentimentIntensityAnalyzer
from nltk import ngrams as nltk_ngrams

DATA_DIR = Path(__file__).parent.parent / "data"
CONVERSATIONS_FILE = DATA_DIR / "conversations.json"
STYLES_DIR = DATA_DIR / "styles"


def ensure_nltk_data():
    """Download required NLTK data packages if not already present."""
    packages = {
        "punkt_tab": "tokenizers/punkt_tab",
        "vader_lexicon": "sentiment/vader_lexicon",
        "stopwords": "corpora/stopwords",
    }
    for package, path in packages.items():
        try:
            nltk.data.find(path)
        except LookupError:
            print(f"  Downloading NLTK data: {package}...")
            nltk.download(package, quiet=True)


def analyze_style(messages, stop_words, sia):
    """Analyze a user's messages to extract style patterns."""
    my_messages = [m for m in messages if m["is_from_me"] and m.get("text")]
    if len(my_messages) < 20:
        return None

    texts = [m["text"] for m in my_messages]
    lengths = [len(t) for t in texts]

    # Capitalization analysis
    starts_lower = sum(1 for t in texts if t and t[0].islower())
    starts_upper = sum(1 for t in texts if t and t[0].isupper())
    total = len(texts)
    if starts_lower / total > 0.8:
        capitalization = "never"
    elif starts_upper / total > 0.8:
        capitalization = "always"
    else:
        capitalization = "mixed"

    # Punctuation
    uses_periods = sum(1 for t in texts if t.endswith(".")) / total
    uses_exclamation = sum(1 for t in texts if "!" in t) / total
    uses_question = sum(1 for t in texts if "?" in t) / total
    uses_ellipsis = sum(1 for t in texts if "..." in t) / total
    uses_commas = sum(1 for t in texts if "," in t) / total
    uses_apostrophes = sum(1 for t in texts if "'" in t) / total

    # Emoji analysis
    emoji_pattern = re.compile(
        "[\U0001f600-\U0001f64f\U0001f300-\U0001f5ff\U0001f680-\U0001f6ff"
        "\U0001f1e0-\U0001f1ff\U00002702-\U000027b0\U000024c2-\U0001f251"
        "\U0001f900-\U0001f9ff\U0001fa00-\U0001fa6f\U0001fa70-\U0001faff"
        "\U00002600-\U000026ff]+",
        flags=re.UNICODE,
    )
    all_emojis = []
    for t in texts:
        all_emojis.extend(emoji_pattern.findall(t))
    emoji_freq = len(all_emojis) / total if total > 0 else 0
    top_emojis = [e for e, _ in Counter(all_emojis).most_common(5)]

    # NLTK tokenization
    all_tokens = []
    all_sentences = []
    for t in texts:
        tokens = word_tokenize(t.lower())
        word_tokens = [tok for tok in tokens if tok.isalpha()]
        all_tokens.extend(word_tokens)
        all_sentences.extend(sent_tokenize(t))

    word_counts = Counter(all_tokens)

    # Sentence complexity (avg words per sentence)
    sentence_word_counts = [len(word_tokenize(s)) for s in all_sentences]
    avg_words_per_sentence = (
        sum(sentence_word_counts) / len(sentence_word_counts)
        if sentence_word_counts
        else 5.0
    )

    # Slang detection
    slang_words = {
        "lmao", "lol", "bruh", "bro", "bet", "nah", "fr", "ngl", "tbh",
        "lowkey", "highkey", "imo", "idk", "idc", "smh", "wya", "wyd",
        "omg", "af", "rn", "fam", "goated", "cooked", "bussin", "cap",
        "slay", "vibe", "lit", "sus", "deadass", "hella",
        "finna", "yall", "aight", "yo", "ong", "ts", "shi", "dawg",
    }
    used_slang = [w for w in slang_words if word_counts.get(w, 0) >= 3]
    slang_level = "high" if len(used_slang) > 5 else "medium" if len(used_slang) > 2 else "low"

    # Stopword-filtered bigrams via NLTK
    filtered_bigrams = []
    for t in texts:
        tokens = [tok.lower() for tok in word_tokenize(t) if tok.isalpha()]
        content_tokens = [tok for tok in tokens if tok not in stop_words]
        filtered_bigrams.extend([" ".join(bg) for bg in nltk_ngrams(content_tokens, 2)])
    top_bigrams = [b for b, c in Counter(filtered_bigrams).most_common(10) if c >= 3]

    # Vocabulary richness (Type-Token Ratio)
    unique_words = set(all_tokens)
    vocabulary_richness = len(unique_words) / len(all_tokens) if all_tokens else 0.0

    # VADER sentiment analysis
    compounds = [sia.polarity_scores(t)["compound"] for t in texts]
    avg_compound = sum(compounds) / len(compounds) if compounds else 0.0
    pos_ratio = sum(1 for c in compounds if c > 0.05) / len(compounds) if compounds else 0.0
    neg_ratio = sum(1 for c in compounds if c < -0.05) / len(compounds) if compounds else 0.0

    if avg_compound > 0.15:
        tone_label = "positive"
    elif avg_compound < -0.15:
        tone_label = "negative"
    elif pos_ratio > 0.4 and neg_ratio > 0.2:
        tone_label = "mixed"
    else:
        tone_label = "neutral"

    # Greeting patterns
    greetings = {"hey", "hi", "hello", "yo", "sup", "whats up", "heyy", "heyyy", "hii", "yoo", "ayy"}
    greeting_patterns = [g for g in greetings if any(t.lower().startswith(g) for t in texts)]

    # Farewell patterns
    farewells = {"bye", "cya", "later", "peace", "gn", "goodnight", "night", "bet", "aight", "ttyl"}
    farewell_patterns = [f for f in farewells if word_counts.get(f, 0) >= 2]

    # Multi-message tendency (consecutive messages from me)
    consecutive_bursts = 0
    burst_lengths = []
    i = 0
    all_msgs = messages  # includes both sides
    while i < len(all_msgs):
        if all_msgs[i]["is_from_me"]:
            burst_start = i
            while i < len(all_msgs) and all_msgs[i]["is_from_me"]:
                i += 1
            burst_len = i - burst_start
            if burst_len > 1:
                consecutive_bursts += 1
                burst_lengths.append(burst_len)
        else:
            i += 1

    total_responses = max(1, sum(1 for j in range(1, len(all_msgs))
                                  if all_msgs[j]["is_from_me"] and not all_msgs[j-1]["is_from_me"]))
    multi_msg_tendency = consecutive_bursts / total_responses if total_responses > 0 else 0.3
    avg_burst = sum(burst_lengths) / len(burst_lengths) if burst_lengths else 1.0

    # Response time analysis
    response_times = []
    for j in range(1, len(all_msgs)):
        if all_msgs[j]["is_from_me"] and not all_msgs[j-1]["is_from_me"]:
            try:
                t1 = datetime.fromisoformat(all_msgs[j-1]["date"])
                t2 = datetime.fromisoformat(all_msgs[j]["date"])
                diff_minutes = (t2 - t1).total_seconds() / 60
                if 0 < diff_minutes < 1440:  # ignore > 24h gaps
                    response_times.append(diff_minutes)
            except (ValueError, TypeError):
                pass

    rt_mean = sum(response_times) / len(response_times) if response_times else 5.0
    rt_std = (sum((t - rt_mean) ** 2 for t in response_times) / len(response_times)) ** 0.5 if len(response_times) > 1 else 3.0

    # Time patterns
    hours = []
    for m in my_messages:
        try:
            dt = datetime.fromisoformat(m["date"])
            hours.append(dt.hour)
        except (ValueError, TypeError):
            pass
    hour_counts = Counter(hours)
    active_hours = [h for h, c in hour_counts.most_common(10)]

    # Topic detection (simple keyword matching)
    topic_keywords = {
        "food": ["food", "eat", "dinner", "lunch", "hungry", "restaurant", "pizza", "sushi", "ramen"],
        "gaming": ["game", "play", "gaming", "xbox", "ps5", "pc", "valorant", "league", "fortnite"],
        "school": ["class", "exam", "midterm", "final", "homework", "prof", "lecture", "study"],
        "sports": ["game", "goal", "score", "team", "play", "win", "lost", "season"],
        "music": ["song", "album", "playlist", "listen", "concert", "spotify"],
        "movies": ["movie", "film", "watch", "netflix", "show", "series", "episode"],
        "travel": ["trip", "travel", "flight", "hotel", "vacation", "airport"],
        "work": ["work", "job", "meeting", "boss", "office", "deadline"],
    }
    topic_scores = {}
    all_text = " ".join(texts).lower()
    for topic, keywords in topic_keywords.items():
        score = sum(all_text.count(k) for k in keywords)
        if score >= 5:
            topic_scores[topic] = score
    common_topics = [t for t, _ in sorted(topic_scores.items(), key=lambda x: -x[1])[:5]]

    def freq_label(ratio):
        if ratio < 0.05:
            return "rarely"
        elif ratio < 0.2:
            return "sometimes"
        elif ratio < 0.5:
            return "often"
        else:
            return "frequently"

    return {
        "message_stats": {
            "total_messages_from_you": len(my_messages),
            "avg_message_length": int(sum(lengths) / len(lengths)),
            "median_message_length": sorted(lengths)[len(lengths) // 2],
            "max_message_length": max(lengths),
            "messages_per_day_avg": round(len(my_messages) / max(1, (len(messages) / 50)), 1),
        },
        "style": {
            "capitalization": capitalization,
            "uses_periods": uses_periods > 0.3,
            "uses_commas": freq_label(uses_commas),
            "uses_exclamation": freq_label(uses_exclamation),
            "uses_question_marks": uses_question > 0.1,
            "uses_ellipsis": uses_ellipsis > 0.05,
            "uses_apostrophes": uses_apostrophes > 0.2,
            "abbreviation_level": slang_level,
            "avg_words_per_sentence": round(avg_words_per_sentence, 1),
        },
        "emoji": {
            "frequency": round(emoji_freq, 3),
            "top_emojis": top_emojis,
            "uses_emoji_as_response": any(emoji_pattern.fullmatch(t) for t in texts),
        },
        "vocabulary": {
            "slang_level": slang_level,
            "top_phrases": sorted(used_slang)[:10] + top_bigrams[:5],
            "greeting_patterns": sorted(greeting_patterns),
            "farewell_patterns": sorted(farewell_patterns),
            "filler_words": [w for w in ["like", "just", "actually", "literally", "basically", "ngl", "tbh", "lowkey"] if word_counts.get(w, 0) >= 5],
            "vocabulary_richness": round(vocabulary_richness, 3),
        },
        "sentiment": {
            "avg_compound": round(avg_compound, 3),
            "tone_label": tone_label,
            "positivity_ratio": round(pos_ratio, 3),
            "negativity_ratio": round(neg_ratio, 3),
        },
        "behavior": {
            "multi_message_tendency": round(min(multi_msg_tendency, 1.0), 2),
            "avg_messages_per_burst": round(avg_burst, 1),
            "response_time_mean_minutes": round(rt_mean, 1),
            "response_time_std_minutes": round(rt_std, 1),
            "initiates_conversations": True,  # TODO: calculate
            "initiation_frequency_per_week": 3.0,  # TODO: calculate
            "tapback_frequency": 0.1,  # TODO: calculate from tapbacks
            "leaves_on_read_frequency": 0.05,  # TODO: calculate
        },
        "topics": {
            "common": common_topics,
            "avoids": [],
            "inside_references": [],
        },
        "time_patterns": {
            "most_active_hours": sorted(active_hours),
            "morning_style": "minimal" if any(h < 10 for h in active_hours) else "inactive",
            "evening_style": "engaged" if any(18 <= h <= 23 for h in active_hours) else "inactive",
            "weekend_vs_weekday": "similar",
        },
    }


def main():
    if not CONVERSATIONS_FILE.exists():
        print(f"Error: {CONVERSATIONS_FILE} not found. Run extract_history.py first.")
        return

    print("Ensuring NLTK data is available...")
    ensure_nltk_data()

    # Initialize shared NLTK resources
    stop_words = set(stopwords.words("english"))
    sia = SentimentIntensityAnalyzer()

    with open(CONVERSATIONS_FILE) as f:
        all_chats = json.load(f)

    STYLES_DIR.mkdir(parents=True, exist_ok=True)

    profiles_generated = 0

    for chat_id, chat_data in all_chats.items():
        if chat_data.get("is_group"):
            continue

        all_msgs = []
        for convo in chat_data.get("conversations", []):
            all_msgs.extend(convo)

        if len(all_msgs) < 50:
            continue

        style = analyze_style(all_msgs, stop_words, sia)
        if style is None:
            continue

        # Extract contact info
        contact_id = chat_id.split(";")[-1]
        display_name = chat_data.get("display_name", contact_id)

        profile = {
            "contact": display_name if display_name else contact_id,
            "phone": contact_id if contact_id.startswith("+") else None,
            "relationship_tier": "friend",  # default, user can edit
            **style,
        }

        # Sanitize filename
        safe_name = re.sub(r'[^\w\-]', '_', display_name or contact_id).lower().strip('_')
        if not safe_name:
            safe_name = contact_id.replace("+", "").replace(" ", "_")

        output_file = STYLES_DIR / f"{safe_name}.json"
        with open(output_file, "w") as f:
            json.dump(profile, f, indent=2)

        profiles_generated += 1
        my_count = style["message_stats"]["total_messages_from_you"]
        print(f"  Generated: {display_name or contact_id} ({my_count} messages from you)")

    print(f"\nGenerated {profiles_generated} style profiles in {STYLES_DIR}")


if __name__ == "__main__":
    main()
