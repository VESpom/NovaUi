#!/usr/bin/env python3
"""Runs test/test_novaui.lua on Lua 5.2 (has bit32, like Roblox) via lupa.

    pip install lupa
    python3 test/run_tests.py            # tests the repo's source.lua
    python3 test/run_tests.py path/dir   # tests <dir>/source.lua (used for mutation checks)
"""
import hashlib
import os
import sys

import lupa.lua52 as lua52

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.dirname(HERE)

# latin-1 maps every byte to one character, so binary strings survive the Python <-> Lua boundary
rt = lua52.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)


def py_sha256(s):
    return hashlib.sha256(s.encode("latin-1")).hexdigest()


def py_kdf(key, salt, rounds):
    # independent re-implementation of the Lua key derivation
    h = hashlib.sha256((salt + "\0" + key).encode("latin-1")).hexdigest()
    for _ in range(2, int(rounds) + 1):
        h = hashlib.sha256((h + salt + key).encode("latin-1")).hexdigest()
    return h


g = rt.globals()
g.SRC_DIR = SRC_DIR
g.py_sha256 = py_sha256
g.py_kdf = py_kdf
rt.execute('package.path = "%s/?.lua;" .. package.path' % HERE.replace("\\", "/"))

with open(os.path.join(HERE, "test_novaui.lua"), encoding="latin-1") as f:
    code = f.read()

failed = rt.eval("function(src) return assert(load(src, '=test_novaui'))() end")(code)
sys.exit(1 if failed else 0)
