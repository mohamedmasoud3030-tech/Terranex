#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Path confinement helpers.

Every component is reduced with os.path.basename before rejoining the trusted
root, so separator/traversal payloads cannot survive into file or process sinks.
"""
from __future__ import annotations

import os


def confine(path: str, root: str) -> str:
    root_rp = os.path.realpath(root)
    rp = os.path.realpath(path)
    try:
        inside = rp == root_rp or os.path.commonpath([rp, root_rp]) == root_rp
    except ValueError:
        inside = False
    if not inside:
        raise ValueError(f"path outside allowed root: {path}")
    rel = os.path.relpath(rp, root_rp)
    parts = []
    for comp in rel.split(os.sep):
        base = os.path.basename(comp)
        if base in ("", ".", ".."):
            raise ValueError(f"unsafe path component: {comp}")
        parts.append(base)
    return os.path.join(root_rp, *parts)
