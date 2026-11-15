#!/usr/bin/env bash
# Shortcut: ./build.sh [release] is ateliertool build.
# Every other step: odin run tools/ateliertool -collection:gt=ext/gui_toolkit/src -out:build/ateliertool -- <command> (help lists them).
cd "$(dirname "$0")" && mkdir -p build && exec odin run tools/ateliertool -collection:gt=ext/gui_toolkit/src -out:build/ateliertool -keep-executable -- build "$@"
