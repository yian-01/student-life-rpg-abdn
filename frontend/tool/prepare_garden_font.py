"""Create a static, renamed OFL font for offline CJK UI. FontTools is dev-only."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools import subset
import argparse

parser=argparse.ArgumentParser();parser.add_argument('source');args=parser.parse_args()
root=Path(__file__).resolve().parents[1]/'assets'/'fonts';root.mkdir(exist_ok=True)
font=TTFont(args.source)
if 'fvar' in font: font=instantiateVariableFont(font,{'wght':400},inplace=True)
options=subset.Options();options.hinting=False
subsetter=subset.Subsetter(options=options)
subsetter.populate(unicodes=set(range(0x20,0x100))|set(range(0x3000,0x3040))|set(range(0x4e00,0xa000))|set(range(0xff00,0xfff0)))
subsetter.subset(font)
for record in font['name'].names:
    replacement={1:'Keyu Garden Serif',2:'Regular',4:'Keyu Garden Serif Regular',6:'KeyuGardenSerif-Regular',16:'Keyu Garden Serif',17:'Regular'}.get(record.nameID)
    if replacement:record.string=replacement.encode(record.getEncoding())
font.save(root/'GardenSerif-Regular.ttf')
(root/'PROVENANCE.txt').write_text('Keyu Garden Serif: static 400-weight Basic Latin/CJK subset of Noto Serif SC, renamed per SIL OFL. Regenerate with tool/prepare_garden_font.py. Original copyright/license metadata retained in font; see OFL.txt.\n',encoding='utf-8')
print('Font bytes:',(root/'GardenSerif-Regular.ttf').stat().st_size)
