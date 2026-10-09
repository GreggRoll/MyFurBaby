"""Create bundled masks for action/idle playback and legacy final-frame holds."""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString

root = Path(__file__).resolve().parents[1]
for period in [3, 4]:
    name = f"FurCycle{period}"
    builder = FontBuilder(1024, isTTF=True)
    order = [".notdef", "space", "colon"] + [f"digit{i}" for i in range(10)] + ["visible", "hidden"]
    builder.setupGlyphOrder(order)
    builder.setupCharacterMap({32: "space", 58: "colon", **{48+i: f"digit{i}" for i in range(10)}})
    drawings = {}
    for glyph in order:
        pen = TTGlyphPen(None)
        if glyph == "visible":
            pen.moveTo((0, 0)); pen.lineTo((1024, 0)); pen.lineTo((1024, 1024)); pen.lineTo((0, 1024)); pen.closePath()
        drawings[glyph] = pen.glyph()
    builder.setupGlyf(drawings)
    builder.setupHorizontalMetrics({glyph: (1024, 0) for glyph in order})
    builder.setupHorizontalHeader(ascent=1024, descent=0)
    builder.setupNameTable({"familyName": name, "styleName": "Regular", "uniqueFontIdentifier": name + "-1",
                           "fullName": name + " Regular", "psName": name + "-Regular", "version": "Version 1.0"})
    builder.setupOS2(sTypoAscender=1024, sTypoDescender=0, usWinAscent=1024, usWinDescent=0)
    builder.setupPost(); builder.setupMaxp()
    rules = [f"sub digit{i//10} digit{i%10} by {'visible' if i % period == 0 else 'hidden'};" for i in range(60)]
    addOpenTypeFeaturesFromString(builder.font, "feature liga {\n" + "\n".join(rules) + "\n} liga;")
    builder.save(root / f"Resources/{name}-Regular.ttf")
    print(f"Generated {name} mask")

# The dynamic timer renders m:ss components separately. Format total seconds as a
# single numeric field instead, then reduce its digits modulo the complete loop.
for period in [12, 13, 14, 22, 23, 24]:
    for mode in (["Loop", "Idle"] if period < 20 else ["Loop", "Rest"]):
        holding = mode == "Rest"
        name = f"Fur{mode}{period}"
        builder = FontBuilder(1024, isTTF=True)
        digits = [f"digit{i}" for i in range(10)]
        states = [f"r{i}" for i in range(period)]
        order = [".notdef", "blank"] + digits + states + ["visible", "hidden"]
        builder.setupGlyphOrder(order)
        builder.setupCharacterMap({**{c:'blank' for c in range(32,127)}, **{48+i: f'digit{i}' for i in range(10)}})
        drawings = {}
        for glyph in order:
            pen = TTGlyphPen(None)
            if glyph == 'visible':
                pen.moveTo((0, 0)); pen.lineTo((1024, 0)); pen.lineTo((1024, 1024)); pen.lineTo((0, 1024)); pen.closePath()
            drawings[glyph] = pen.glyph()
        builder.setupGlyf(drawings)
        builder.setupHorizontalMetrics({glyph: (1024, 0) for glyph in order})
        builder.setupHorizontalHeader(ascent=1024, descent=0)
        builder.setupNameTable({'familyName': name, 'styleName': 'Regular', 'uniqueFontIdentifier': name+'-1',
            'fullName': name+' Regular', 'psName': name+'-Regular', 'version': 'Version 1.0'})
        builder.setupOS2(sTypoAscender=1024, sTypoDescender=0, usWinAscent=1024, usWinDescent=0)
        builder.setupPost(); builder.setupMaxp()
        rules = ['lookup pairs {']
        rules += [f'sub digit{value//10} digit{value%10} by r{value%period};' for value in range(100)]
        rules += ['} pairs;', 'lookup number {']
        def output(value):
            value %= period
            active = (value < 10 and value % 2 == 0) if mode == 'Idle' else (value >= period-20 if holding else value == 0)
            return 'visible' if active else 'hidden'
        # Longest matches come first. Five decimal digits cover >27 hours, while
        # widget timeline entries normally realign their reference every hour.
        rules += [f'sub r{a} r{b} digit{c} by {output(a*1000+b*10+c)};' for a in range(period) for b in range(period) for c in range(10)]
        rules += [f'sub r{a} r{b} by {output(a*100+b)};' for a in range(period) for b in range(period)]
        rules += [f'sub r{a} digit{b} by {output(a*10+b)};' for a in range(period) for b in range(10)]
        rules += ['} number;', 'lookup finish {']
        rules += [f'sub r{a} by {output(a)};' for a in range(period)]
        rules += [f'sub digit{a} by {output(a)};' for a in range(10)]
        rules += ['} finish;', 'feature liga { lookup pairs; lookup number; lookup finish; } liga;']
        addOpenTypeFeaturesFromString(builder.font, '\n'.join(rules))
        builder.save(root/f'Resources/{name}-Regular.ttf')
        print(f'Generated {name} seconds mask')
