"""Create an original alternating-digit mask font for the public timer experiment."""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

root = Path(__file__).resolve().parents[1]
font = FontBuilder(1024, isTTF=True)
glyphs = [".notdef", "space", "colon"] + [f"digit{i}" for i in range(10)]
font.setupGlyphOrder(glyphs)
font.setupCharacterMap({32: "space", 58: "colon", **{48+i: f"digit{i}" for i in range(10)}})
drawings = {}
for name in glyphs:
    pen = TTGlyphPen(None)
    if name.startswith("digit") and int(name[-1]) % 2:
        pen.moveTo((0, 0)); pen.lineTo((1024, 0)); pen.lineTo((1024, 1024)); pen.lineTo((0, 1024)); pen.closePath()
    drawings[name] = pen.glyph()
font.setupGlyf(drawings)
font.setupHorizontalMetrics({name: (1024, 0) for name in glyphs})
font.setupHorizontalHeader(ascent=1024, descent=0)
font.setupNameTable({"familyName": "FurBlink", "styleName": "Regular", "uniqueFontIdentifier": "MyFurBaby-FurBlink-1", "fullName": "FurBlink Regular", "psName": "FurBlink-Regular", "version": "Version 1.0"})
font.setupOS2(sTypoAscender=1024, sTypoDescender=0, usWinAscent=1024, usWinDescent=0)
font.setupPost(); font.setupMaxp()
font.save(root / "Resources/FurBlink-Regular.ttf")
print("Generated Resources/FurBlink-Regular.ttf")
