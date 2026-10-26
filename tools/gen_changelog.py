#!/usr/bin/env python3
"""根据 git 提交记录生成 Release 更新日志（Markdown）。

被 .github/workflows/publish_app_release.yml 与
.github/workflows/publish_tv_app_release.yaml 调用，产出四部分：

  1. 可选的 ``--header``（例如 "# Android TV"）
  2. ``version_desc``：``--version-desc-file`` 里的手写摘要，原样保留
  3. 自动 "What's Changed"：按 conventional commit 的类型分组，
     分类口径与 ``.github/release.yml`` 保持一致
  4. "Full Changelog" 对比链接

只依赖 git 与标准库，不需要网络。

版本号 / tag 的推导顺序：
  * 传了 ``--to`` 时，先把它当成完整 tag 名查（``v1.8.9``），查不到再当成
    裸版本号按 ``--tag-prefix`` 拼（``1.8.9`` → ``v1.8.9``）；
  * 没传时从 ``--version-desc-file`` 的 ``version`` 字段按前缀拼 tag。
    tag 不存在（比如还没推 tag 的分支构建）时，对比终点退化为 HEAD。
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# 与 .github/release.yml 的 categories 一一对应（顺序也一致）
CATEGORIES: list[tuple[str, str, tuple[str, ...]]] = [
    ("⚠️ Breaking Changes", ("breaking", "semver-major")),
    ("🚀 Features", ("feat", "feature", "enhancement", "semver-minor")),
    ("🐛 Bug Fixes", ("fix", "bug")),
    ("⚡ Performance", ("perf", "performance")),
    ("♻️ Refactors", ("refactor",)),
    ("📝 Documentation", ("docs", "documentation")),
    ("👷 Build & CI", ("build", "ci")),
    ("🔧 Chores & Dependencies", ("chore", "dependencies", "semver-patch")),
]
FALLBACK_TITLE = "🧩 Other Changes"

CONVENTIONAL_RE = re.compile(
    r"^(?P<type>[a-zA-Z]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<desc>.+)$"
)


def run_git(args: list[str]) -> str:
    """跑一条 git 命令，失败时抛 RuntimeError。"""
    try:
        proc = subprocess.run(
            ["git", *args],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as exc:
        raise RuntimeError("找不到 git 命令，请在 checkout 之后运行") from exc
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or "").strip().splitlines()
        raise RuntimeError(
            "git {} 失败: {}".format(" ".join(args), detail[-1] if detail else exc)
        ) from exc
    return proc.stdout


def tag_exists(tag: str) -> bool:
    return bool(run_git(["tag", "-l", "--", tag]).strip())


def read_version_desc(path: str) -> tuple[str, str]:
    """读 version_desc 文件，返回 (version, version_desc)。"""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RuntimeError(f"版本文件不存在: {path}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"版本文件不是合法 JSON: {path}") from exc

    version = str(data.get("version") or "").strip()
    desc = str(data.get("version_desc") or "").strip()
    return version, desc


def resolve_to_tag(to: str | None, version: str, tag_prefix: str) -> str | None:
    """把 ``--to`` 或版本号解析成真实存在的 tag；不存在返回 None。"""
    candidates: list[str] = []
    if to:
        candidates.append(to)
        if not to.startswith(tag_prefix):
            candidates.append(f"{tag_prefix}{to}")
    if version:
        candidates.append(f"{tag_prefix}{version}")

    for candidate in candidates:
        if tag_exists(candidate):
            return candidate
    return None


def resolve_previous_tag(previous_tag: str, to_tag: str | None) -> str | None:
    """auto 时取目标的上一个 tag；取不到（首次发布）返回 None。"""
    if previous_tag != "auto":
        return previous_tag or None

    # to_tag 存在时，它自己就是本次要发的 tag，要取它前一个；
    # 没有就取 HEAD 能看到的最近一个 tag
    ref = f"{to_tag}^" if to_tag else "HEAD"
    try:
        return run_git(["describe", "--tags", "--abbrev=0", ref]).strip() or None
    except RuntimeError:
        return None


def collect_commits(prev: str | None, to_ref: str) -> list[str]:
    """取 (prev, to_ref] 区间的提交标题。"""
    revision_range = f"{prev}..{to_ref}" if prev else to_ref
    try:
        out = run_git(["log", "--format=%s", "--no-merges", revision_range])
    except RuntimeError:
        # 区间非法（prev 与 to_ref 无共同祖先等），退化为全部历史
        out = run_git(["log", "--format=%s", "--no-merges", to_ref])
    return [line.strip() for line in out.splitlines() if line.strip()]


def group_commits(subjects: list[str]) -> dict[str, list[str]]:
    """按 conventional commit 类型分组，返回「标题 -> 提交说明列表」。"""
    by_type: dict[str, list[str]] = {}
    seen: set[tuple[str, str]] = set()

    for subject in subjects:
        match = CONVENTIONAL_RE.match(subject)
        if not match:
            by_type.setdefault(FALLBACK_TITLE, []).append(subject)
            continue

        raw_type = match.group("type").lower()
        is_breaking = bool(match.group("bang")) or raw_type == "breaking"
        desc = match.group("desc").strip()
        if not desc:
            continue
        # scope 保留在说明里，看起来与 GitHub 原生生成的一致
        scope = match.group("scope")
        text = f"**{scope}**: {desc}" if scope else desc

        key = (raw_type, text)
        if key in seen:
            continue
        seen.add(key)

        title = CATEGORIES[0][0] if is_breaking else FALLBACK_TITLE
        if not is_breaking:
            for cat_title, cat_types in CATEGORIES:
                if raw_type in cat_types:
                    title = cat_title
                    break
        by_type.setdefault(title, []).append(text)

    return by_type


def build_markdown(
    header: str | None,
    version_desc: str,
    groups: dict[str, list[str]],
    repo: str,
    prev: str | None,
    to_tag: str | None,
    to_ref: str,
) -> str:
    parts: list[str] = []
    if header:
        parts.append(f"{header}\n")
    if version_desc:
        parts.append(f"{version_desc}\n")

    if groups:
        parts.append("## What's Changed\n")
        for cat_title, _ in CATEGORIES:
            items = groups.get(cat_title)
            if not items:
                continue
            parts.append(f"**{cat_title}**\n")
            for item in items:
                parts.append(f"* {item}")
            parts.append("")
        other = groups.get(FALLBACK_TITLE)
        if other:
            parts.append(f"**{FALLBACK_TITLE}**\n")
            for item in other:
                parts.append(f"* {item}")
            parts.append("")

    if prev:
        to_label = to_tag or to_ref
        parts.append(
            f"**Full Changelog**: https://github.com/{repo}/compare/{prev}...{to_label}\n"
        )
    elif to_tag is None:
        # 既没有上一个 tag，也没有当前 tag：没有任何可比对的锚点
        parts.append("> 本次发布没有可对比的历史 tag，已列出当前分支上的全部提交。\n")

    return "\n".join(parts).rstrip() + "\n"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="根据 git 提交记录生成 Release 更新日志（Markdown）"
    )
    parser.add_argument(
        "--to",
        help="目标版本：tag 名（v1.8.9）或裸版本号（1.8.9）。不传时从版本文件推导",
    )
    parser.add_argument(
        "--previous-tag",
        default="auto",
        help='上一个 tag，"auto"（默认）时自动取目标的上一个 tag',
    )
    parser.add_argument("--repo", required=True, help="owner/name，用于 Full Changelog 链接")
    parser.add_argument(
        "--version-desc-file", required=True, help="版本 JSON 文件（含 version / version_desc）"
    )
    parser.add_argument("--header", help='附加标题，例如 "# Android TV"')
    parser.add_argument(
        "--tag-prefix",
        default="v",
        help="版本号到 tag 的前缀，App 用 v（默认），TV 用 tv_v",
    )
    parser.add_argument("--output", required=True, help="输出 markdown 文件路径")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    version, version_desc = read_version_desc(args.version_desc_file)
    if not version and not args.to:
        print(
            f"::error::{args.version_desc_file} 里没有 version 字段，也没有传 --to",
            file=sys.stderr,
        )
        return 1

    to_tag = resolve_to_tag(args.to, version, args.tag_prefix)
    to_ref = to_tag or "HEAD"
    if to_tag is None:
        print(
            f"::warning::没有找到与版本匹配的 tag（{args.to or version}），"
            "对比终点退化为 HEAD，Full Changelog 链接可能不是最终地址",
            file=sys.stderr,
        )

    prev = resolve_previous_tag(args.previous_tag, to_tag)
    if prev is None:
        print("::warning::没有找到上一个 tag，本次按首次发布处理", file=sys.stderr)

    subjects = collect_commits(prev, to_ref)
    groups = group_commits(subjects)
    markdown = build_markdown(
        header=args.header,
        version_desc=version_desc,
        groups=groups,
        repo=args.repo,
        prev=prev,
        to_tag=to_tag,
        to_ref=to_ref,
    )

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(markdown, encoding="utf-8")
    print(f"已生成 {out}（{len(subjects)} 条提交，{sum(len(v) for v in groups.values())} 条入册）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
