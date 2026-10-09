"""Create the original empty TrueType template used for runtime sbix motion fonts."""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

root = Path(__file__).resolve().parents[1]
font = FontBuilder(1024, isTTF=True)
glyphs = [".notdef", "space", "colon"] + [f"digit{i}" for i in range(10)]
font.setupGlyphOrder(glyphs)
font.setupCharacterMap({32: "space", 58: "colon", **{48 + i: f"digit{i}" for i in range(10)}})
font.setupGlyf({name: TTGlyphPen(None).glyph() for name in glyphs})
font.setupHorizontalMetrics({name: (1024, 0) for name in glyphs})
font.setupHorizontalHeader(ascent=1024, descent=0)
font.setupNameTable({"familyName": "FurMotionTemplate", "styleName": "Regular",
    "uniqueFontIdentifier": "MyFurBaby-MotionTemplate-1", "fullName": "FurMotionTemplate Regular",
    "psName": "FurMotionTemplate-Regular", "version": "Version 1.0"})
font.setupOS2(sTypoAscender=1024, sTypoDescender=0, usWinAscent=1024, usWinDescent=0)
font.setupPost()
font.setupMaxp()
font.save(root / "Resources/FurMotionTemplate.ttf")
print("Generated Resources/FurMotionTemplate.ttf")
