#!/usr/bin/env python3
"""生成随包分发的中文衬线字体子集（思源宋体 / Noto Serif SC）。

手工风格（纸墨、素笺）的正文字体此前指向系统自带衬线体，字体族名写的是通用词
`serif`。这条路在 Android 上能命中 AOSP 的 NotoSerifCJK，但在 iOS 上
`serif` 解析不到，CJK 字符直接走引擎默认字体（苹方，黑体），
`fontFamilyFallback` 里的具名字体根本没机会被查询——衬线在 iOS 上从未生效。

随包字体把字体族变成一个一定解析得到的名字，同时让
`ThemeStyleForm.readingWeightFloor` 从「下限 + 听设备的」变成精确取值。

用法：
    python3 scripts/fonts/build_serif_subset.py [--traditional]

输出 assets/fonts/NotoSerifSC-Subset.ttf。产物已签入仓库，**只有改字符集或换
字体版本时才需要重跑**，日常构建不依赖本脚本。
"""

from __future__ import annotations

import argparse
import os
import urllib.parse
import urllib.request
from pathlib import Path

from fontTools import subset as ft_subset
from fontTools.varLib import instancer as ft_instancer

# fonttools 默认把当前时间写进 head 表，同样的输入会产出不同的字节。产物是要签入
# 仓库的，重跑一次就多一个无意义的 5MB diff——钉死时间戳让构建可复现。
os.environ.setdefault("SOURCE_DATE_EPOCH", "0")

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = REPO_ROOT / "assets" / "fonts"
OUT_FONT = OUT_DIR / "NotoSerifSC-Subset.ttf"
OUT_LICENSE = OUT_DIR / "OFL.txt"

# pubspec 里声明的族名必须和这个一致。
FAMILY_NAME = "NotoSerifSC"

SOURCE_FONT_URL = (
    "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/"
    "NotoSerifSC%5Bwght%5D.ttf"
)
SOURCE_LICENSE_URL = (
    "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/OFL.txt"
)

# 保留的字重区间。下限取 400 而不是原始的 200：
#   - 应用最细只用到 w400，砍掉 200–400 不损失任何取值；
#   - 更要紧的是这样一来**默认实例就是 400**。原始字体的默认实例是 200（ExtraLight），
#     一旦某条渲染路径漏了 fontVariations，整段文字会变成极细体。把下限抬到 400
#     等于给这个隐患上了保险，而且实测体积不变（deltas 只需覆盖更窄的区间）。
WEIGHT_RANGE = "wght=400:900"

# 版式特性：不保留 vert / vrt2（应用没有竖排）。
LAYOUT_FEATURES = "kern,liga,locl,ccmp,palt"


def build_charset(include_traditional: bool) -> str:
    chars: set[str] = set()

    # GB2312 全量：6763 个汉字 + 符号区，覆盖简体中文日常书写。
    for hi in range(0xA1, 0xFF):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass

    if include_traditional:
        # Big5 常用字（一级字区 0xA440–0xC67E），覆盖繁体引文。
        for hi in range(0xA4, 0xC7):
            for lo in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
                try:
                    chars.add(bytes([hi, lo]).decode("big5"))
                except UnicodeDecodeError:
                    pass

    # 应用支持 7 种界面语言（de/en/es/fr/ja/ko/zh），用户还会用任意语言记笔记。
    # 覆盖情况见下，**这不是随手划的范围**：
    #   - de / es / fr：重音字母全在拉丁补充区，下面第二条已覆盖；
    #   - ja：假名 GB2312 自带了大半，这里补齐整块。日文汉字会用简体字形渲染，
    #     这是用简体中文字体的固有代价，靠子集解决不了；
    #   - ko：**源字体根本不含谚文**（Noto Serif SC 的谚文音节数为 0），
    #     韩文一定会落到 fontFamilyFallback 的系统字体，这里加什么都没用；
    #   - ru / el：源字体只有 66 个西里尔字母和 49 个希腊字母，下面第二、三条
    #     已经把它们全收进来了。
    ranges = [
        range(0x20, 0x7F),      # ASCII
        range(0xA0, 0x180),     # 拉丁补充 + 拉丁扩展 A
        range(0x370, 0x400),    # 希腊字母
        range(0x400, 0x500),    # 西里尔字母
        range(0x2000, 0x206F),  # 通用标点（含中文引号、省略号、破折号）
        range(0x3000, 0x303F),  # CJK 标点
        range(0x3040, 0x3100),  # 平假名 + 片假名
        range(0xFF00, 0xFFEF),  # 全角字符（含半角片假名）
    ]
    for r in ranges:
        chars.update(chr(cp) for cp in r)
    # 正文里真的会出现的零散符号：欧元、摄氏度、项目符号、星标、箭头。
    chars.update(chr(cp) for cp in (0x20AC, 0x2103, 0x2109, 0x25CF, 0x25CB,
                                    0x2605, 0x2606, 0x2190, 0x2191, 0x2192, 0x2193))
    return "".join(sorted(chars))


def download(url: str, dest: Path) -> None:
    """下载到 [dest]，已存在则跳过。

    先校验 scheme 再打开：`urlopen` 认 `file:` 和自定义 scheme，上面那两个常量
    改错一个字符就会从「下载字体」变成「读本地任意文件」。这里的 URL 目前都是
    写死的常量，这道检查是给以后改常量的人留的。
    """
    scheme = urllib.parse.urlparse(url).scheme
    if scheme != "https":
        raise SystemExit(f"只允许 https，拿到的是 {scheme!r}：{url}")
    if dest.exists():
        print(f"跳过下载（已存在）：{dest.name}")
        return
    print(f"下载 {url}")
    # nosec 的依据是上面那三行 scheme 校验，不是「这行看着没事」——
    # 静态分析盯 urlopen 盯的就是 file:/ 与自定义 scheme，那条路已经堵死。
    with urllib.request.urlopen(url, timeout=180) as response:  # nosec B310
        dest.write_bytes(response.read())


def fix_name_table(font_path: Path) -> None:
    """把 name 表改回 Regular。

    收窄字重轴之后默认实例已经是 w400，但 `--update-name-table` 只在生成静态实例时
    改名，可变字体仍然顶着源文件的 "ExtraLight"。Flutter 认的是 pubspec 里的
    `family`，所以这一步不影响渲染，纯粹是别让以后排查字体问题的人被名字带偏。
    """
    from fontTools.ttLib import TTFont

    font = TTFont(font_path)
    name = font["name"]
    for record in name.names:
        text = record.toUnicode()
        if "ExtraLight" in text:
            record.string = text.replace("ExtraLight", "Regular").strip()
    name.setName(FAMILY_NAME, 1, 3, 1, 0x409)
    name.setName("Regular", 2, 3, 1, 0x409)
    font.save(font_path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--traditional",
        action="store_true",
        help="额外收录 Big5 一级常用繁体字（体积约 +1.6MB）",
    )
    parser.add_argument(
        "--work-dir",
        default=None,
        help="下载与中间产物目录，默认使用系统临时目录",
    )
    args = parser.parse_args()

    import tempfile

    work_dir = (
        Path(args.work_dir)
        if args.work_dir
        else Path(tempfile.gettempdir()) / "thoughtecho-fonts"
    )
    work_dir.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    source_font = work_dir / "NotoSerifSC-VF.ttf"
    download(SOURCE_FONT_URL, source_font)
    download(SOURCE_LICENSE_URL, OUT_LICENSE)

    charset = build_charset(args.traditional)
    charset_file = work_dir / "charset.txt"
    charset_file.write_text(charset, encoding="utf-8")
    print(f"字符集：{len(charset)} 个字符"
          f"（{'含繁体' if args.traditional else '简体'}）")

    # 直接调 fontTools 的 Python API，不起子进程：pyftsubset / fonttools 是否在
    # PATH 上取决于安装方式，而且子进程那条路要么被静态分析盯上、要么得靠
    # 抑制注释糊过去。库调用没有这些问题，报错也直接是 Python 异常。
    subset_file = work_dir / "subset.ttf"
    ft_subset.main([
        str(source_font),
        f"--text-file={charset_file}",
        f"--output-file={subset_file}",
        f"--layout-features={LAYOUT_FEATURES}",
        "--no-hinting",
    ])

    # 收窄字重轴，顺带把默认实例定到 400 并刷新 name 表。
    ft_instancer.main([
        str(subset_file),
        WEIGHT_RANGE,
        "-o", str(OUT_FONT),
        "--update-name-table",
    ])

    fix_name_table(OUT_FONT)

    size_mb = OUT_FONT.stat().st_size / 1024 / 1024
    print(f"产物：{OUT_FONT.relative_to(REPO_ROOT)}  {size_mb:.2f} MB")


if __name__ == "__main__":
    main()
