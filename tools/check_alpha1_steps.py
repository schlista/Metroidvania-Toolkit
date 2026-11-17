"""Check docs/metroidvania/ALPHA1_STEPS.md against the alpha.1 sittings of TEST_SESSIONS.md.

ALPHA1_STEPS.md is the plain step list the user runs before alpha.1; TEST_SESSIONS.md stays the
maintainer reference. This check confirms that:

- the run-order list at the top names every alpha.1 sitting once, and the sections follow it;
- every alpha.1 sitting (marked **alpha.1** in the session index) has a section;
- every check id of a sitting appears in an HTML comment of that sitting's section, and no
  comment names an id the sitting does not have;
- every line of a section after "Do the following:" is a numbered step, numbered from 1;
- no step shows "(setup)", "Shared procedures" or a check id outside a comment;
- each section ends with the step 'Send Claude: "<id> done", and the numbers of any steps
  that did not match.'

Usage: py -B tools/check_alpha1_steps.py   (exit 0 when every rule holds, 1 otherwise)
"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SESSIONS = ROOT / "docs" / "metroidvania" / "TEST_SESSIONS.md"
STEPS = ROOT / "docs" / "metroidvania" / "ALPHA1_STEPS.md"

CHECK_ID = re.compile(r"\bSC-[A-Z0-9]+-\d+\b")
INDEX_ROW = re.compile(r"^\| \[(?P<part>[A-Z]\d+[a-z])\]\(#part-[a-z0-9]+\) \| \*\*alpha\.1\*\* \|", re.M)
COMMENT = re.compile(r"<!--.*?-->", re.S)
HEADING = re.compile(r"^## (?P<part>[A-Z]\d+[a-z])\. (?P<title>\S.*) \((?P<minutes>\d+) minutes\)$")
ORDER_ITEM = re.compile(r"^(?P<number>\d+)\. (?P<part>[A-Z]\d+[a-z])\. \S.* \(\d+ minutes\)$")
STEP = re.compile(r"^(?P<number>\d+)\. (?P<text>\S.*)$")
LEAD = "Do the following:"
FORBIDDEN = ("(setup)", "Shared procedures")


def last_step(part):
    return 'Send Claude: "%s done", and the numbers of any steps that did not match.' % part


def alpha1_parts(sessions_text):
    """The sittings the session index marks alpha.1, in index order."""
    return INDEX_ROW.findall(sessions_text)


def sitting_body(sessions_text, part):
    """The text of one sitting in TEST_SESSIONS.md, from its anchor to the next sitting or session."""
    match = re.search(r'<a id="part-%s"></a>\n(.*?)(?=\n<a id="part-|\n## |\Z)' % re.escape(part.lower()),
                      sessions_text, re.S)
    return match.group(1) if match else None


def sections(steps_text):
    """(preamble lines, [(part, heading line number, [(line number, line)])]) of ALPHA1_STEPS.md."""
    preamble, found, current = [], [], None
    for number, line in enumerate(steps_text.splitlines(), 1):
        heading = HEADING.match(line)
        if heading:
            current = (heading.group("part"), number, [])
            found.append(current)
        elif line.startswith("## "):
            current = (None, number, [])
            found.append(current)
        elif current is None:
            preamble.append((number, line))
        else:
            current[2].append((number, line))
    return preamble, found


def section_problems(part, lines, expected_ids):
    problems = []
    where = "ALPHA1_STEPS.md %s" % part
    lead = [number for number, line in lines if line == LEAD]
    if len(lead) != 1:
        return ["%s: needs exactly one %r line" % (where, LEAD)]
    before = [line for number, line in lines if number < lead[0] and line.strip()]
    if len(before) > 1:
        problems.append("%s: at most one sentence may stand between the heading and %r" % (where, LEAD))
    steps = []
    for number, line in lines:
        if number <= lead[0] or not line.strip():
            continue
        match = STEP.match(line)
        if not match:
            problems.append("%s line %d: not a numbered step: %s" % (where, number, line[:60]))
            continue
        steps.append((number, int(match.group("number")), match.group("text")))
    if not steps:
        return problems + ["%s: has no steps" % where]
    for index, (number, step_number, text) in enumerate(steps, 1):
        if step_number != index:
            problems.append("%s line %d: step %d should be numbered %d" % (where, number, step_number, index))
        visible = COMMENT.sub("", text)
        if "<!--" in visible or "-->" in visible:
            problems.append("%s step %d: unclosed comment" % (where, step_number))
        for word in FORBIDDEN:
            if word in visible:
                problems.append("%s step %d: shows %r" % (where, step_number, word))
        for check in CHECK_ID.findall(visible):
            problems.append("%s step %d: shows the check id %s outside a comment" % (where, step_number, check))
    if COMMENT.sub("", steps[-1][2]).strip() != last_step(part):
        problems.append("%s: the last step must read %r" % (where, last_step(part)))
    found = set()
    for _number, _step, text in steps:
        for comment in COMMENT.findall(text):
            found.update(CHECK_ID.findall(comment))
    for check in sorted(expected_ids - found):
        problems.append("%s: no step comment carries %s" % (where, check))
    for check in sorted(found - expected_ids):
        problems.append("%s: comment names %s, which the sitting in TEST_SESSIONS.md does not have" % (where, check))
    return problems


def run(sessions_text, steps_text):
    """Every problem found, as text; an empty list means the file passes."""
    problems = []
    parts = alpha1_parts(sessions_text)
    if not parts:
        return ["TEST_SESSIONS.md: the session index marks no sitting alpha.1"]
    preamble, found = sections(steps_text)
    order = []
    for number, line in preamble:
        match = ORDER_ITEM.match(line)
        if match:
            order.append(match.group("part"))
            if int(match.group("number")) != len(order):
                problems.append("ALPHA1_STEPS.md line %d: run-order item should be numbered %d" % (number, len(order)))
        visible = COMMENT.sub("", line)
        for check in CHECK_ID.findall(visible):
            problems.append("ALPHA1_STEPS.md line %d: shows the check id %s outside a comment" % (number, check))
    if sorted(order) != sorted(parts) or len(order) != len(set(order)):
        problems.append("ALPHA1_STEPS.md: the run-order list must name each alpha.1 sitting once: %s"
                        % ", ".join(parts))
    for part, number, _lines in found:
        if part is None:
            problems.append("ALPHA1_STEPS.md line %d: section heading is not '## <id>. <title> (<n> minutes)'"
                            % number)
    named = [part for part, _number, _lines in found if part]
    for part in parts:
        if part not in named:
            problems.append("ALPHA1_STEPS.md: no section for %s" % part)
    for part in sorted(set(named) - set(parts)):
        problems.append("ALPHA1_STEPS.md: %s is not an alpha.1 sitting" % part)
    if len(named) != len(set(named)):
        problems.append("ALPHA1_STEPS.md: a sitting has more than one section")
    if [part for part in named if part in order] != order:
        problems.append("ALPHA1_STEPS.md: the sections must follow the run-order list")
    for part, _number, lines in found:
        if part not in parts:
            continue
        body = sitting_body(sessions_text, part)
        if body is None:
            problems.append("TEST_SESSIONS.md: no sitting text for %s" % part)
            continue
        problems += section_problems(part, lines, set(CHECK_ID.findall(body)))
    return problems


def main(argv=None):
    # Problem lines quote the file (arrows, accents); a redirected Windows console is not UTF-8.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    problems = run(SESSIONS.read_text(encoding="utf-8"), STEPS.read_text(encoding="utf-8"))
    for problem in problems:
        print(problem)
    if problems:
        print("[alpha1-steps] FAIL: %d problem(s)" % len(problems))
        return 1
    print("[alpha1-steps] PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
