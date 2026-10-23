#!/usr/bin/env python3
"""Add new strings to the String Catalog.

Usage: add_strings.py <Localizable.xcstrings> <strings.json>

strings.json is {"English text": {"en": "...", "de": "...", ... all 15 languages}}. The script checks that every
language is there and that placeholders (%@, %lld, %1$@ ...) match the English text. Translations that differ from the
English text are stored as "needs_review" (machine drafts, see docs/localization.md); an identical text (a product
name such as "Apple Watch") is "translated". Existing keys are replaced. The file keeps its compact, sorted format.

.github/workflows/watch.yml applies tools/l10n/pending-strings.json with this script and removes the file.
"""
import json
import re
import sys

LANGS = {"en", "de", "fr", "it", "es", "pt-PT", "nl", "pl", "uk", "ro", "cs", "sv", "el", "hu", "tr"}


def tokens(text):
    found = re.findall(r'%(?:\d+\$)?(?:lld|ld|d|@)|\$\{[^}]+\}', text)
    return sorted(re.sub(r'^%\d+\$', '%', t) for t in found)


def main(catalog_path, new_path):
    catalog = json.loads(open(catalog_path, encoding='utf-8').read())
    new = json.load(open(new_path, encoding='utf-8'))
    added = replaced = 0
    for key, translations in new.items():
        assert set(translations) == LANGS, (key, LANGS ^ set(translations))
        for lang, value in translations.items():
            assert value and value.strip() == value, (key, lang)
            assert tokens(value) == tokens(translations['en']), (key, lang, value)
        units = {}
        for lang, value in translations.items():
            state = "translated" if lang == "en" or value == translations['en'] else "needs_review"
            units[lang] = {"stringUnit": {"state": state, "value": value}}
        if key in catalog['strings']:
            replaced += 1
        else:
            added += 1
        catalog['strings'][key] = {"extractionState": "manual", "localizations": units}
    open(catalog_path, 'w', encoding='utf-8').write(
        json.dumps(catalog, ensure_ascii=False, separators=(',', ':'), sort_keys=True))
    print('added', added, 'replaced', replaced, 'total', len(catalog['strings']))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
