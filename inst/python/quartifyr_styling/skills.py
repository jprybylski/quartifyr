"""Bundled coding-agent skill files this package exports (issue #57).

Hand-authored Claude Skills-format ``SKILL.md`` content -- not generated
from anything else, unlike e.g. a style YAML's own docx build -- so
what's checked here (``tests/python/test_skills_content.py``) is the
Skills format contract each file must satisfy (frontmatter/body present),
not the prose itself. Mirrors ../deckifyr's identical
``inst/python/deckifyr/skills/`` + ``_SKILL_NAMES`` pattern (issue #50).
"""

from __future__ import annotations

import shutil
from pathlib import Path

_SKILL_NAMES = ("quartifyr-style-config", "quartifyr-shell-authoring")


class SkillsError(Exception):
    """Raised when exporting bundled skill files fails."""


def _skills_dir() -> Path:
    return Path(__file__).resolve().parent / "skills"


def export_skills(directory: str | Path, *, force: bool = False) -> dict:
    target = Path(directory)

    # Only refuse on the exact destination files, not the whole target
    # directory's non-emptiness -- the target may be e.g. `.claude/skills`,
    # which can legitimately already hold other, unrelated skills.
    conflicts = [
        str(target / name / "SKILL.md")
        for name in _SKILL_NAMES
        if (target / name / "SKILL.md").exists()
    ]
    if conflicts and not force:
        raise SkillsError(f"{', '.join(conflicts)} already exist (use --force to overwrite)")

    created = []
    for name in _SKILL_NAMES:
        source = _skills_dir() / name / "SKILL.md"
        destination = target / name / "SKILL.md"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        created.append(str(destination))

    return {"directory": str(target), "created": created}
