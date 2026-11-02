"""Offline approximation of Buta's animated mesh and current hat placement.

Uses original local WAD data, without extracting or modifying it. The mesh strips
are approximated; verify the result in-game too.
Run from the repository root: python tools/preview_buta.py
"""
from pathlib import Path
import argparse
import re
import struct
import zlib

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
import numpy as np
from scipy.spatial.transform import Rotation

parser = argparse.ArgumentParser(description='Techniczny podgląd modelu Buty i jego czapki')
parser.add_argument('--frame', type=int, default=0, help='Klatka animacji postoju')
parser.add_argument('--scale', type=float, help='Opcjonalny rozmiar czapki do porównania')
args = parser.parse_args()
REPO = Path(__file__).resolve().parent.parent
ROOT = REPO

def find_data(name, ext):
    for path in (REPO / 'data').rglob('*.wad'):
        raw = path.read_bytes()
        info = zlib.decompress(raw[struct.unpack_from('<I', raw, 4)[0]:])
        offset = 20
        for p in range(0, len(info), 28):
            nm, ex, compressed, size, children, kind, _ = struct.unpack_from('<4s4sIIIII', info, p)
            if not children and kind != 1:
                if nm[::-1].lower() == name.encode().lower() and ex[::-1] == ext.encode():
                    content = raw[offset:offset + compressed]
                    return zlib.decompress(content) if kind == 2 or (kind != 0 and compressed < size) else content
                offset += compressed
    raise FileNotFoundError(f'{name}.{ext}')

md = find_data('buta', 'SXMD')
scale = struct.unpack_from('<f', find_data('buta', 'SAXS'))[0]
num_bones, bone_offset, vertex_offset = struct.unpack_from('<III', md, 28)
stance = find_data('BUs1', 'SXSK')
num_frames, _, animation_bones = struct.unpack_from('<HfH', stance, 2)
assert animation_bones == num_bones
frame = args.frame
if not 0 <= frame < num_frames:
    raise ValueError(f'Klatka musi być w zakresie 0..{num_frames-1}')
frame_offset = struct.unpack_from('<I', stance, 12 + frame*12 + 8)[0]
rotations = []
bones = []
for i in range(num_bones):
    qx, qy, qz, qw = struct.unpack_from('<hhhh', stance, frame_offset + i*8)
    local = Rotation.from_quat([-qx, -qz, qy, qw])
    if i == 0:
        rotations.append(local)
        bones.append(np.zeros(3))
        continue
    x, y, z, parent = struct.unpack_from('<fffH', md, bone_offset + 140*i)
    bones.append(bones[parent] + rotations[parent].apply(scale * np.array([-x, -z, y])))
    rotations.append(rotations[parent] * local)

parts = []
for part in range(md[0]):
    po = struct.unpack_from('<I', md, 40 + part*4)[0]
    ring_count, extra = struct.unpack_from('<BB', md, po)
    rings = []
    for r in range(ring_count):
        ro = struct.unpack_from('<I', md, po + 36 + r*4)[0]
        count = md[ro] + extra*256
        start = struct.unpack_from('<I', md, ro + 4)[0]
        points = []
        for j in range(count):
            ids = struct.unpack_from('<HHH', md, start + j*10)
            p = np.zeros(3)
            for index in ids:
                if index == 65535:
                    continue
                x, y, z, bone, weight = struct.unpack_from('<hhhhH', md, vertex_offset + index*16)
                p += (bones[bone] + rotations[bone].apply(scale*np.array([-x, -z, y]))) * weight/16384
            points.append(p)
        if len(points) >= 3:
            rings.append(np.array(points))
    faces = []
    for a, b in zip(rings, rings[1:]):
        n = max(len(a), len(b))
        for k in range(n):
            i, j = k*len(a)//n, k*len(b)//n
            ii, jj = ((k+1)*len(a)//n)%len(a), ((k+1)*len(b)//n)%len(b)
            faces.extend(([a[i], b[j], a[ii]], [a[ii], b[j], b[jj]]))
    parts.append(faces)

code = (REPO / 'source/christmas_hat.d').read_text()
block = code.split('void addButaHat', 1)[1].split('}', 1)[0]
match = re.search(r'addHat!B\(model,\s*(\d+),\s*Vector3f\(([^)]+)\),\s*([\d.]+)f\)', block)
bone = int(match[1])
base = np.array([float(x.strip().rstrip('f')) for x in match[2].split(',')])
hat_scale = float(match[3])
if args.scale is not None:
    if args.scale <= 0:
        raise ValueError('Rozmiar musi być dodatni')
    hat_scale = args.scale

def hat_faces(rings):
    coords = []
    for x, y, z, rx, ry in rings:
        coords.append([bones[bone]+rotations[bone].apply(base+hat_scale*np.array([x+rx*np.cos(a), y+0.10+ry*np.sin(a), z-0.18])) for a in np.linspace(0, 2*np.pi, 20, endpoint=False)])
    return [[coords[i][k], coords[i][(k+1)%20], coords[i+1][(k+1)%20], coords[i+1][k]] for i in range(len(coords)-1) for k in range(20)]

hat = [
    (hat_faces([(0,-.1,.18,.16,.19),(0,-.1,.25,.16,.19)]), '#f0eee5'),
    (hat_faces([(0,-.1,.245,.15,.18),(0,-.1,.34,.12,.14),(.03,-.1,.44,.08,.10),(.11,-.1,.49,.045,.055),(.17,-.1,.46,.025,.03)]), '#bf1723'),
    (hat_faces([(.18,-.1,.40,.008,.008),(.18,-.1,.42,.05,.05),(.18,-.1,.46,.065,.065),(.18,-.1,.50,.05,.05),(.18,-.1,.52,.008,.008)]), '#f0eee5'),
]
fig = plt.figure(figsize=(12, 6), facecolor='#e7ebef')
for i, (elev, azim, title) in enumerate([(10,-90,'Widok 1'),(10,0,'Widok 2')], 1):
    ax = fig.add_subplot(1,2,i,projection='3d',computed_zorder=True)
    all_faces, all_colors = [], []
    for faces in parts:
        if faces:
            triangles = np.asarray(faces)
            normals = np.cross(triangles[:,1]-triangles[:,0], triangles[:,2]-triangles[:,0])
            lengths = np.maximum(np.linalg.norm(normals, axis=1), 1e-9)
            normals /= lengths[:,None]
            light = np.array([.3,-.4,.86])
            shade = .47 + .43*np.abs(normals @ light)
            colors = np.column_stack((shade*.9, shade*.95, shade, np.ones(len(shade))))
            all_faces.extend(faces)
            all_colors.extend(colors)
    for faces, color in hat:
        from matplotlib.colors import to_rgba
        all_faces.extend(faces)
        all_colors.extend([to_rgba(color)]*len(faces))
    ax.add_collection3d(Poly3DCollection(all_faces, facecolors=all_colors, edgecolors='none'))
    cx, cy, cz = bones[bone]
    ax.set_xlim(cx-.8,cx+.8)
    ax.set_ylim(cy-.8,cy+.8)
    ax.set_zlim(cz-.45,cz+1.15)
    ax.set_box_aspect((1,1,1))
    ax.view_init(elev=elev, azim=azim)
    ax.set_axis_off()
    ax.set_title(title, fontsize=14)
fig.suptitle(f'Buta — podgląd techniczny, klatka {frame}, skala {hat_scale:.2f}',fontsize=15)
fig.tight_layout()
out = ROOT / (f'podglad_buty_{hat_scale:.2f}.png' if args.scale is not None else 'podglad_buty.png')
fig.savefig(out, dpi=170)
print(out)
print('head bone absolute', bones[bone], 'hat base', base)
