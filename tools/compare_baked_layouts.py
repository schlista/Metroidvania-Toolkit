#!/usr/bin/env python3
"""Prove two bakes build the same rooms, whatever their file layout (CP05d/e).

docs/metroidvania/STAGE_7_WORLD_SCALE_PLAN.md slice f "2.3 Rows" CP05d step 3
and CP05e. Create Rooms used to write one generated prototype per object (the
per-object layout); since CP05e it writes only content-addressed prototypes
shared by many objects, with per-object values on each room instance as
overrides (the shared layout). File names and file counts differ between the
two, so a byte golden master cannot compare a bake from before CP05e with one
from after it. This tool compares meaning instead, per room and per instance
id:

- the instance's position, rotation, scale and children;
- each component: its resource, position, rotation and scale, and its script
  properties merged as Defold merges them (the instance's overrides win over
  the prototype's values, gameobject_ddf.proto InstanceDesc and ComponentDesc);
- each embedded component's type and data, with its transform.

A path into developer/rooms/generated/ is replaced by what that file holds, so
a hull or tilemap compares by content whatever its name. Factories and every
developer/config file other than tiled_object_config.lua must be identical;
--allow-config-diff names a further config file whose source changed between
the two trees (CP05e itself edits config_schema.lua and INDEX.md).

Usage:
  py tools/compare_baked_layouts.py --left <baked root> --right <baked root>
      [--allow-config-diff developer/config/<file>] ...
      Compares two workspaces that are already baked, for example a fixture
      workspace baked before CP05e (per-object) and one baked after it.

CP05e removed the bake_layout switch, so the tool can no longer bake one tree
both ways; tools/test.ps1 no longer runs it.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

GENERATED = '/developer/rooms/generated/'
CONFIG = Path('developer/config/tiled_object_config.lua')
TOKEN = re.compile(r'\s+|#[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}:]|[^\s{}:"\']+')
ESCAPES = {'n': 10, 't': 9, 'r': 13, 'a': 7, 'b': 8, 'f': 12, 'v': 11,
           '\\': 92, '"': 34, "'": 39, '?': 63}
NUMBER = re.compile(r'^-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$')


def decode_string(raw: str) -> str:
    """Protobuf text string literal (octal, hex and named escapes) to text."""
    body, out, i = raw[1:-1], bytearray(), 0
    while i < len(body):
        ch = body[i]
        if ch != '\\':
            out += ch.encode('utf-8')
            i += 1
            continue
        code = body[i + 1]
        if code in ESCAPES:
            out.append(ESCAPES[code])
            i += 2
        elif code in '01234567':
            digits = re.match(r'[0-7]{1,3}', body[i + 1:]).group(0)
            out.append(int(digits, 8))
            i += 1 + len(digits)
        elif code == 'x':
            digits = re.match(r'[0-9a-fA-F]{1,2}', body[i + 2:]).group(0)
            out.append(int(digits, 16))
            i += 2 + len(digits)
        else:
            raise ValueError(f'Unsupported string escape \\{code}')
    return out.decode('utf-8')


def parse_proto(text: str) -> dict:
    """Protobuf text format to {field: [values]}; adjacent strings join."""
    tokens = [t for t in TOKEN.findall(text) if not t.isspace() and not t.startswith('#')]
    index = 0

    def message(nested: bool) -> dict:
        nonlocal index
        result: dict = {}
        while index < len(tokens) and tokens[index] != '}':
            key = tokens[index]
            index += 1
            if index < len(tokens) and tokens[index] == ':':
                index += 1
                token = tokens[index]
                index += 1
                if token[0] in '"\'':
                    value = decode_string(token)
                    while index < len(tokens) and tokens[index][0] in '"\'':
                        value += decode_string(tokens[index])
                        index += 1
                else:
                    value = ('scalar', token)
            elif index < len(tokens) and tokens[index] == '{':
                index += 1
                value = message(True)
            else:
                raise ValueError(f"Expected ':' or '{{' after {key}")
            result.setdefault(key, []).append(value)
        if nested:
            if index >= len(tokens):
                raise ValueError('Unclosed protobuf message')
            index += 1
        return result

    result = message(False)
    if index != len(tokens):
        raise ValueError('Unexpected closing brace')
    return result


def one(message: dict, key: str, default=None):
    values = message.get(key, [])
    if len(values) > 1:
        raise ValueError(f'Duplicate field {key}')
    return values[0] if values else default


def number_or_text(value: str):
    """'1.000000' and '1' compare equal; vectors compare per component."""
    parts = [p.strip() for p in value.split(',')]
    if all(NUMBER.match(p) for p in parts):
        numbers = tuple(round(float(p), 5) + 0.0 for p in parts)
        return numbers[0] if len(numbers) == 1 else numbers
    return value


class Workspace:
    """One baked project root; generated resources resolve to their content."""

    def __init__(self, root: Path):
        self.root = Path(root)
        self.cache: dict = {}

    def text(self, resource: str):
        path = self.root / resource.lstrip('/')
        return path.read_text(encoding='utf-8') if path.is_file() else None

    def resolve(self, resource: str):
        if not resource.startswith(GENERATED):
            return resource
        if resource not in self.cache:
            self.cache[resource] = ('missing', resource)
            text = self.text(resource)
            if text is None:
                return self.cache[resource]
            kind = resource.rsplit('.', 1)[-1]
            if kind == 'go':
                value = ('go', self.prototype(parse_proto(text)))
            elif kind in ('collection', 'tilemap', 'tilesource', 'atlas'):
                value = (kind, text.replace('\r\n', '\n'))
            else:
                value = (kind, self.normalize(parse_proto(text)))
            self.cache[resource] = value
        return self.cache[resource]

    def normalize(self, value, key=None):
        if isinstance(value, dict):
            return tuple(sorted((k, tuple(self.normalize(v, k) for v in values))
                                for k, values in value.items()))
        if isinstance(value, tuple):
            return number_or_text(value[1])
        if value.startswith(GENERATED):
            return self.resolve(value)
        if key == 'data' and re.search(r'[{:]', value):
            try:
                return ('data', self.normalize(parse_proto(value)))
            except (ValueError, IndexError):
                return value
        return value

    def transform(self, message: dict) -> dict:
        fields = {}
        for key in ('position', 'rotation', 'scale', 'scale3'):
            value = one(message, key)
            if value is not None:
                fields[key] = self.normalize(value)
        if 'scale' in fields and not isinstance(one(message, 'scale'), dict):
            fields['scale'] = number_or_text(one(message, 'scale')[1])
        return fields

    def prototype(self, go: dict) -> dict:
        components = {}
        for component in go.get('components', []):
            cid = one(component, 'id')
            properties = {one(p, 'id'): (number_or_text(str(self.scalar(one(p, 'value')))),
                                         self.scalar(one(p, 'type')))
                          for p in component.get('properties', [])}
            components[cid] = {'component': self.normalize(one(component, 'component')),
                               'transform': self.transform(component), 'properties': properties}
        for component in go.get('embedded_components', []):
            components[one(component, 'id')] = {
                'type': one(component, 'type'),
                'data': self.normalize(one(component, 'data', ''), 'data'),
                'transform': self.transform(component)}
        return components

    @staticmethod
    def scalar(value):
        return value[1] if isinstance(value, tuple) else value

    def instance(self, instance: dict, embedded: bool) -> tuple[dict, list[str]]:
        """Merged model of one collection instance, and override errors."""
        if embedded:
            components = self.prototype(parse_proto(one(instance, 'data', '')))
        else:
            resolved = self.resolve(one(instance, 'prototype'))
            if resolved[0] != 'go':
                return {'prototype': resolved}, []
            components = {cid: {**value, 'properties': dict(value.get('properties', {}))}
                          for cid, value in resolved[1].items()}
        problems = []
        for override in instance.get('component_properties', []):
            cid = one(override, 'id')
            target = components.get(cid)
            if target is None or 'properties' not in target:
                problems.append(f'overrides {cid}, which is not a script component of its prototype')
                continue
            for p in override.get('properties', []):
                target['properties'][one(p, 'id')] = (number_or_text(str(self.scalar(one(p, 'value')))),
                                                      self.scalar(one(p, 'type')))
        model = {'components': components, 'transform': self.transform(instance),
                 'children': sorted(instance.get('children', []))}
        return model, problems

    def rooms(self) -> dict:
        folder = self.root / 'developer/rooms/collections'
        return {p.stem: p for p in sorted(folder.glob('*.collection')) if not p.name.startswith('_')}

    def generated_counts(self) -> tuple[int, int]:
        folder = self.root / GENERATED.strip('/')
        top = sum(1 for p in folder.glob('*') if p.is_file() and not p.name.startswith('.'))
        shared = folder / 'shared'
        return top, (sum(1 for p in shared.glob('*') if p.is_file()) if shared.is_dir() else 0)


def describe(a, b, path=''):
    """First difference between two models, as a readable path."""
    if isinstance(a, dict) and isinstance(b, dict):
        for key in sorted(set(a) | set(b), key=str):
            if key not in a:
                return f'{path}/{key}: only in the shared layout'
            if key not in b:
                return f'{path}/{key}: only in the per-object layout'
            found = describe(a[key], b[key], f'{path}/{key}')
            if found:
                return found
        return None
    if a != b:
        left, right = repr(a), repr(b)
        return f'{path}: {left[:160]} != {right[:160]}'
    return None


def compare(left_root: Path, right_root: Path, allow_config=()) -> list[str]:
    """left and right are two baked workspace roots, for example a per-object
    bake from before CP05e and a shared one from after it."""
    left, right = Workspace(left_root), Workspace(right_root)
    errors: list[str] = []
    left_rooms, right_rooms = left.rooms(), right.rooms()
    if set(left_rooms) != set(right_rooms):
        errors.append(f'room collections differ: {sorted(set(left_rooms) ^ set(right_rooms))}')
    instances = 0
    for room in sorted(set(left_rooms) & set(right_rooms)):
        docs = [parse_proto(w.rooms()[room].read_text(encoding='utf-8')) for w in (left, right)]
        for key in sorted(set(docs[0]) | set(docs[1])):
            if key in ('instances', 'embedded_instances'):
                continue
            values = [tuple(w.normalize(v, key) for v in d.get(key, [])) for w, d in ((left, docs[0]), (right, docs[1]))]
            if values[0] != values[1]:
                errors.append(f'{room}: collection field {key} differs')
        for key in ('instances', 'embedded_instances'):
            sides = []
            for workspace, doc in ((left, docs[0]), (right, docs[1])):
                models = {}
                for instance in doc.get(key, []):
                    iid = one(instance, 'id')
                    if iid in models:
                        errors.append(f'{room}: duplicate instance id {iid}')
                    model, problems = workspace.instance(instance, key == 'embedded_instances')
                    errors.extend(f'{room}/{iid}: {p}' for p in problems)
                    models[iid] = model
                sides.append(models)
            only = sorted(set(sides[0]) ^ set(sides[1]))
            if only:
                errors.append(f'{room}: instance ids differ: {only[:10]}')
            for iid in sorted(set(sides[0]) & set(sides[1])):
                instances += 1
                difference = describe(sides[0][iid], sides[1][iid])
                if difference:
                    errors.append(f'{room}/{iid}{difference}')
    for folder in ('developer/rooms/factories', 'developer/config'):
        names = {p.relative_to(left_root).as_posix() for p in (left_root / folder).rglob('*') if p.is_file()}
        names |= {p.relative_to(right_root).as_posix() for p in (right_root / folder).rglob('*') if p.is_file()}
        for name in sorted(names - {CONFIG.as_posix()} - set(allow_config)):
            a, b = left_root / name, right_root / name
            if not (a.is_file() and b.is_file() and a.read_bytes() == b.read_bytes()):
                errors.append(f'{name} differs between the bakes')
    print(f'compared {len(set(left_rooms) & set(right_rooms))} rooms, {instances} instances')
    for label, workspace in (('left', left), ('right', right)):
        top, shared = workspace.generated_counts()
        print(f'{label}: {top} generated files, {shared} in shared/')
    return errors


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--left', type=Path, required=True, help='first baked workspace root')
    parser.add_argument('--right', type=Path, required=True, help='second baked workspace root')
    parser.add_argument('--allow-config-diff', action='append', default=[], metavar='PATH',
                        help='a developer/config file allowed to differ (repo-relative)')
    args = parser.parse_args(argv)
    errors = compare(args.left, args.right, args.allow_config_diff)
    for error in errors[:60]:
        print('DIFF', error)
    if len(errors) > 60:
        print(f'... {len(errors) - 60} more')
    print('PASS: both bakes build the same rooms' if not errors else f'FAIL: {len(errors)} differences')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
