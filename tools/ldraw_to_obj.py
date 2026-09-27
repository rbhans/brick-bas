#!/usr/bin/env python3
"""Bake a selected LDraw part and its dependency closure to a Godot-ready OBJ.

The complete LDraw library is a build-time input only. The output folder receives
the selected top-level DAT files, every referenced primitive/subpart, and meshes.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
from pathlib import Path


IDENTITY = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0)


def transform_point(matrix: tuple[float, ...], point: tuple[float, float, float]) -> tuple[float, float, float]:
    a, b, c, d, e, f, g, h, i, x, y, z = matrix
    px, py, pz = point
    return (
        a * px + b * py + c * pz + x,
        d * px + e * py + f * pz + y,
        g * px + h * py + i * pz + z,
    )


def compose(parent: tuple[float, ...], child: tuple[float, ...]) -> tuple[float, ...]:
    pa, pb, pc, pd, pe, pf, pg, ph, pi, px, py, pz = parent
    ca, cb, cc, cd, ce, cf, cg, ch, ci, cx, cy, cz = child
    return (
        pa * ca + pb * cd + pc * cg,
        pa * cb + pb * ce + pc * ch,
        pa * cc + pb * cf + pc * ci,
        pd * ca + pe * cd + pf * cg,
        pd * cb + pe * ce + pf * ch,
        pd * cc + pe * cf + pf * ci,
        pg * ca + ph * cd + pi * cg,
        pg * cb + ph * ce + pi * ch,
        pg * cc + ph * cf + pi * ci,
        pa * cx + pb * cy + pc * cz + px,
        pd * cx + pe * cy + pf * cz + py,
        pg * cx + ph * cy + pi * cz + pz,
    )


def transform_is_mirrored(matrix: tuple[float, ...]) -> bool:
    a, b, c, d, e, f, g, h, i, _x, _y, _z = matrix
    determinant = (
        a * (e * i - f * h)
        - b * (d * i - f * g)
        + c * (d * h - e * g)
    )
    return determinant < 0.0


class Baker:
    def __init__(self, library: Path, source_output: Path, scale: float) -> None:
        self.library = library
        self.source_output = source_output
        self.scale = scale
        self.dependencies: set[str] = set()
        self.vertices: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, int, int]] = []

    def resolve(self, name: str) -> tuple[Path, str]:
        normalized = name.replace("\\", "/").lower()
        candidates = [
            (self.library / "parts" / normalized, f"parts/{normalized}"),
            (self.library / "p" / normalized, f"p/{normalized}"),
            (self.library / normalized, normalized),
        ]
        for path, relative in candidates:
            if path.is_file():
                return path, relative
        raise FileNotFoundError(f"LDraw dependency not found: {name}")

    def add_face(self, points: list[tuple[float, float, float]], reverse: bool) -> None:
        # LDraw Y points down. Flip it for Godot, then reverse the winding once.
        converted = [(x * self.scale, -y * self.scale, z * self.scale) for x, y, z in points]
        if reverse:
            converted.reverse()
        start = len(self.vertices) + 1
        self.vertices.extend(converted)
        if len(converted) == 3:
            self.faces.append((start, start + 1, start + 2))
        else:
            self.faces.append((start, start + 1, start + 2))
            self.faces.append((start, start + 2, start + 3))

    def parse(self, name: str, matrix: tuple[float, ...] = IDENTITY, inherited_invert: bool = False) -> None:
        path, relative = self.resolve(name)
        self.dependencies.add(relative)
        winding_cw = False
        invert_next = False
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            fields = raw.strip().split()
            if not fields:
                continue
            if fields[0] == "0":
                upper = raw.upper()
                if "BFC CERTIFY CW" in upper and "CCW" not in upper:
                    winding_cw = True
                elif "BFC CERTIFY CCW" in upper:
                    winding_cw = False
                if "BFC INVERTNEXT" in upper:
                    invert_next = True
                continue
            if fields[0] == "1" and len(fields) >= 15:
                values = [float(value) for value in fields[2:14]]
                child = (
                    values[3], values[4], values[5],
                    values[6], values[7], values[8],
                    values[9], values[10], values[11],
                    values[0], values[1], values[2],
                )
                self.parse(" ".join(fields[14:]), compose(matrix, child), inherited_invert ^ invert_next)
                invert_next = False
                continue
            if fields[0] in {"3", "4"}:
                count = 3 if fields[0] == "3" else 4
                numbers = [float(value) for value in fields[2:2 + count * 3]]
                points = [
                    transform_point(matrix, tuple(numbers[index:index + 3]))
                    for index in range(0, len(numbers), 3)
                ]
                # The Godot coordinate conversion reflects Y. Mirrored LDraw
                # reference matrices and BFC INVERTNEXT each flip winding too.
                reverse = (not winding_cw) ^ inherited_invert ^ transform_is_mirrored(matrix)
                self.add_face(points, reverse)

    def copy_sources(self) -> None:
        for relative in sorted(self.dependencies):
            source = self.library / relative
            target = self.source_output / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    def write_obj(self, target: Path, part_id: str) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("w", encoding="utf-8") as output:
            output.write(f"# Baked from official LDraw part {part_id}.dat\n")
            output.write(f"o ldraw_{part_id}\n")
            for x, y, z in self.vertices:
                output.write(f"v {x:.7f} {y:.7f} {z:.7f}\n")
            # LDraw type-2/type-5 edge information is not emitted by this small
            # baker, so a global OBJ smoothing group incorrectly rounds every
            # brick corner and produces melted/cut-off highlights. Keep polygon
            # normals hard until an edge-aware normal pass is implemented.
            output.write("s off\n")
            for a, b, c in self.faces:
                output.write(f"f {a} {b} {c}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--parts", nargs="+", required=True)
    parser.add_argument("--scale", type=float, default=0.025, help="meters per LDraw unit")
    parser.add_argument("--merge", action="store_true", help="retain existing selected-part records")
    args = parser.parse_args()

    manifest_path = args.output / "selection.json"
    manifest: dict[str, object] = {
        "source": "https://library.ldraw.org/library/updates/complete.zip",
        "meters_per_ldu": args.scale,
        "parts": {},
    }
    if args.merge and manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for part_id in args.parts:
        baker = Baker(args.library, args.output / "source", args.scale)
        baker.parse(f"{part_id}.dat")
        baker.copy_sources()
        baker.write_obj(args.output / "meshes" / f"{part_id}.obj", part_id)
        part_path, _ = baker.resolve(f"{part_id}.dat")
        header = part_path.read_text(encoding="utf-8", errors="replace").splitlines()[:8]
        manifest["parts"][part_id] = {
            "header": header,
            "dependencies": sorted(baker.dependencies),
            "vertices": len(baker.vertices),
            "triangles": len(baker.faces),
        }
        print(f"{part_id}: {len(baker.vertices)} vertices, {len(baker.faces)} triangles, {len(baker.dependencies)} DAT files")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
