"""Pack minishlab/potion-base-8M (bf8b056651a2c21b8d2565580b8569da283cab23).

Arguments: model.safetensors, vocab.txt, output.bin. Vectors are signed int8
with a per-token Float32 scale, preserving token magnitudes when averaging.
"""
import array
import json
import struct
import sys
from pathlib import Path

source, vocabulary, destination = map(Path, sys.argv[1:])
with source.open("rb") as model:
    header_size, = struct.unpack("<Q", model.read(8))
    header = json.loads(model.read(header_size))["embeddings"]
    rows, dimensions = header["shape"]
    words = vocabulary.read_bytes()
    assert header["dtype"] == "F32" and len(words.splitlines()) == rows
    model.seek(8 + header_size + header["data_offsets"][0])
    with destination.open("wb") as packed:
        packed.write(struct.pack("<4sIII", b"PJV1", rows, dimensions, len(words)))
        packed.write(words)
        for _ in range(rows):
            vector = struct.unpack(f"<{dimensions}f", model.read(4 * dimensions))
            scale = max(map(abs, vector)) / 127 or 1
            packed.write(struct.pack("<f", scale))
            packed.write(array.array("b", (round(value / scale) for value in vector)).tobytes())
