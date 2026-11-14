#!/usr/bin/env python3
"""Build bundled dictionaries with the vendored, dependency-free compilers."""
import pathlib
import subprocess
import sys

directory = pathlib.Path(__file__).resolve().parents[1] / "Vendor/McBopomofo/Source/Data"
commands = [
    ["curation.builders.frequency_builder"],
    ["curation.compilers.main_compiler", "--heterophony1", "heterophony1.list", "--heterophony2", "heterophony2.list",
     "--heterophony3", "heterophony3.list", "--phrase_freq", "PhraseFreq.txt", "--bpmf_mappings", "BPMFMappings.txt",
     "--bpmf_base", "BPMFBase.txt", "--punctuations", "BPMFPunctuations.txt", "--symbols", "Symbols.txt",
     "--macros", "Macros.txt", "--output", "data-raw.txt"],
    ["curation.compilers.postprocess", "--input", "data-raw.txt", "--directive", "Postprocess.txt", "--output", "data.txt"],
    ["curation.compilers.plain_bpmf_compiler", "--bpmf_base", "BPMFBase.txt", "--punctuations", "BPMFPunctuations.txt",
     "--output", "data-plain-bpmf.txt"],
    ["curation.builders.phrase_deriver", "data.txt", "associated-phrases-v2.txt", "associated-punctuation.txt"],
]
for command in commands:
    subprocess.run([sys.executable, "-m", *command], cwd=directory, check=True)
