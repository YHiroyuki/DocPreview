#!/usr/bin/env python3
"""github-markdown-css(light/dark) の配色を Tokyo Night / Tokyo Night Light に置換して
ui/vendor/tokyonight-{light,dark}.css を生成する。
入力: scripts/ に置いた元 CSS か、npm の github-markdown-css パッケージ（引数でパスを指定）。
使い方: scripts/gen-tokyonight-css.py <github-markdown-css のディレクトリ>
"""
import re, sys, pathlib

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(__file__).resolve().parent.parent / "Sources/DocPreview/Resources/ui/vendor"

MAPS = {
    "light": {
        "#ffffff": "#d5d6db", "#f6f8fa": "#cbccd1", "#1f2328": "#343b58", "#59636e": "#6a6f8e",
        "#d1d9e0": "#b4b5b9", "#0969da": "#34548a", "#0550ae": "#34548a", "#d1242f": "#8c4351",
        "#cf222e": "#8c4351", "#82071e": "#8c4351", "#953800": "#965027", "#8250df": "#5a4a78",
        "#6639ba": "#5a4a78", "#116329": "#485e30", "#1a7f37": "#485e30", "#0a3069": "#166775",
        "#9a6700": "#8f5e15", "#818b98": "#8990b3", "#3b2300": "#343b58", "#fff8c5": "#dcd3b4",
        "#ffebe9": "#dccdd2", "#ffd8b5": "#dcc9b8", "#dafbe1": "#c9d6c6",
    },
    "dark": {
        "#f0f6fc": "#c0caf5", "#9198a1": "#7982a9", "#f85149": "#f7768e", "#3d444d": "#3b4261",
        "#151b23": "#16161e", "#0d1117": "#1a1b26", "#d2a8ff": "#bb9af7", "#a5d6ff": "#7dcfff",
        "#7ee787": "#9ece6a", "#4493f8": "#7aa2f7", "#ffdfb6": "#ff9e64", "#ffdcd7": "#f7768e",
        "#ffa657": "#ff9e64", "#ff7b72": "#f7768e", "#f2cc60": "#e0af68", "#d29922": "#e0af68",
        "#aff5b4": "#9ece6a", "#ab7df8": "#bb9af7", "#79c0ff": "#7dcfff", "#3fb950": "#9ece6a",
        "#1f6feb": "#7aa2f7", "#da3633": "#f7768e", "#9e6a03": "#e0af68", "#8957e5": "#bb9af7",
        "#238636": "#9ece6a", "#033a16": "#283a2a", "#1158c7": "#3d59a1", "#656c76": "#565f89", "#bb8009": "#e0af68", "#b62324": "#db4b4b", "#67060c": "#3a2530", "#5a1e02": "#3a2c2a",
    },
}

for mode, mapping in MAPS.items():
    css = (src / f"github-markdown-{mode}.css").read_text()
    def sub(m):
        h = m.group(0)
        base, alpha = h[:7].lower(), h[7:]
        return mapping.get(base, base) + alpha if base in mapping else h
    css = re.sub(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?\b", sub, css)
    (out / f"tokyonight-{mode}.css").write_text(css)
    left = sorted({h[:7].lower() for h in re.findall(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?\b", css)} - set(mapping.values()))
    print(mode, "未変換:", left)
