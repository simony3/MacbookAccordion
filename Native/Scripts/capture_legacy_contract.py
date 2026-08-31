#!/usr/bin/env python3
"""Extract the legacy contract without initializing Pygame, HID, or audio output.
Run with the existing Python environment (numpy required), then `swift test`.
The generated fixture is committed so normal native development needs only Xcode.
"""
import ast
import json
import math
from pathlib import Path
import threading
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
tree = ast.parse((ROOT / 'lid_accordion.py').read_text())
namespace = {'np': np, 'threading': threading, 'SAMPLE_RATE': 44100}
selected = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.ClassDef)) and n.name in ('midi_to_freq', 'PolyAccordionSynth')]
exec(compile(ast.Module(body=selected, type_ignores=[]), 'legacy_dsp', 'exec'), namespace)
synth = namespace['PolyAccordionSynth']()
main = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'main')
def assigned(name):
    return next(n.value for n in main.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in n.targets))
def literal(node):
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and node.value.id == 'synth':
        return getattr(synth, node.attr)
    return ast.literal_eval(node)
params = []
for call in assigned('params').elts:
    a = [literal(v) for v in call.args]
    params.append(dict(zip(['id','label','initial','minimum','maximum','step','format','group','inverted'],a+[False] if len(a)==8 else a)))
key_names = {'COMMA': ',', 'PERIOD': '.', 'SLASH': '/', 'SEMICOLON': ';'}
keys = []
for node in tree.body:
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id in ['WHITE_Q','BLACK_1','WHITE_Z','BLACK_A'] for t in node.targets):
        for pair in node.value.elts:
            label=pair.elts[0].attr[2:]
            keys.append({'label': key_names.get(label,label.upper()), 'midi':ast.literal_eval(pair.elts[1])})
presets = ast.literal_eval(assigned('sound_presets'))
p = {x['id']:x['initial'] for x in params}
# Extract the actual legacy bellows statements as our numerical oracle.
loop = next(n for n in main.body if isinstance(n, ast.While))
start = next(i for i,n in enumerate(loop.body) if isinstance(n, ast.Assign) and any(isinstance(t,ast.Name) and t.id=='dt_vel' for t in n.targets))
end = next(i for i,n in enumerate(loop.body) if isinstance(n, ast.Expr) and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Attribute) and n.value.func.attr=='set_bellows')
model_code=compile(ast.Module(body=loop.body[start:end],type_ignores=[]),'legacy_bellows','exec')
from types import SimpleNamespace
state={'by_key':{k:SimpleNamespace(value=v) for k,v in p.items()},'air':0.,'bellows':0.,'prev_angle':45.,'prev_t':0.}
trace=[]
now=0
for angle,dt in [(45,1/60),(48,1/60),(60,0.02),(59.99,1/60),(110,0.033),(90,1/60)]+[(90,1/60)]*180+[(80,0.02),(0,0.05)]:
    now+=dt
    state.update(angle=angle,dt=dt,now=now)
    exec(model_code,state)
    trace.append({k:state[k] for k in ['angle','dt','air','bellows','vel']})
# Cover duplicate note sources, held-note retuning, releases, and block phase continuity.
synth.noise_amount=0
synth.set_bellows(0.72)
audio=[]
for index in range(40):
    if index==0: synth.note_on('q',60)
    if index==3: synth.note_on('i',72); synth.note_on('z',72)
    if index==7: synth.retune('q',72); synth.retune('i',84); synth.retune('z',84)
    if index==10: synth.note_off('i')
    if index==13: synth.note_off('q'); synth.note_off('z')
    audio.extend(float(v) for v in synth.generate_frames(256))
fixture={'parameters':params,'keys':keys,'presets':presets,'bellows':trace,'audio':audio}
out=ROOT/'Native/Tests/LegacyContract.json'
out.write_text(json.dumps(fixture, ensure_ascii=False, separators=(',',':'))+'\n')
print(f'Captured {len(params)} parameters, {len(keys)} keys, {len(presets)} presets, {len(trace)} bellows frames, {len(audio)} audio samples.')
