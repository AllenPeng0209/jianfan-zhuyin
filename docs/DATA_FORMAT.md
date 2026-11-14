# Offline data formats

All strings use UTF-8. Formats are versioned so an older client can preserve data it cannot understand.

## Personal phrases

The engine's editable text file is `data.txt`. Each normal line contains a word and a hyphen-separated Bopomofo reading. Comments and existing extra fields are preserved when supported words are edited. The current reading grid supports at most eight syllables per entry; a short reading may expand to a longer word.

JSON phrase export contains normal word and reading pairs:

```json
{
  "schemaVersion": 1,
  "entries": [
    {"phrase": "星河計畫", "reading": "ㄒㄧㄥ-ㄏㄜˊ-ㄐㄧˋ-ㄏㄨㄚˋ"}
  ]
}
```

Imports validate the entire batch before merging and deduplicating. Full recovery of legacy fields, settings and learning uses a backup of the data folder rather than only a phrase JSON export.

## Learned selections

`learning-v1.json` contains a `schemaVersion` of 1, an `overrides` array and an `associations` array. Override entries contain `key`, `value`, `count`, `timestamp` and `forceHighScore`. The context key comes from the shared UserOverrideModel algorithm. Association entries contain `prefixReading`, `prefixValue`, `reading`, `value`, `count` and `timestamp`.

Timestamps are Unix seconds. Association ranking uses frequency with a 30-day recency half-life and preserves baseline order for equal scores. The Mac selection model uses the same half-life. Learning records are bounded; the primary JSON file is limited to 4 MiB and has an atomic local backup.

Clear operations reset both the current memory and its recovery backup. Newer unknown schemas are preserved instead of overwritten. Learning and phrase data are private user data and must never be committed to the source repository or attached to public build artifacts.
