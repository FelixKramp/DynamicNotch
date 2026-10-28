#!/usr/bin/env python3
"""Claude-Code-Hook für DynamicNotch.

Schreibt pro Sitzung den Fortschritt nach
~/Library/Application Support/DynamicNotch/Claude/<session>.json.
DynamicNotch liest die Dateien und zeigt sie in der Notch.

Der Hook darf nie etwas ausgeben und nie fehlschlagen: Bei UserPromptSubmit
landet stdout im Kontext von Claude, ein Fehler würde jeden Schritt stören.
"""

import json
import os
import sys
import tempfile
import time

STATE_DIR = os.path.expanduser("~/Library/Application Support/DynamicNotch/Claude")
PLAN_TOOLS = {"mcp__ccd_turn__update_plan", "TodoWrite"}
AGENT_TOOLS = {"Agent", "Task"}

TOOL_LABELS = {
    "Bash": "Terminal",
    "Read": "Liest",
    "Edit": "Bearbeitet",
    "MultiEdit": "Bearbeitet",
    "Write": "Schreibt",
    "NotebookEdit": "Bearbeitet",
    "Grep": "Sucht",
    "Glob": "Sucht",
    "WebSearch": "Websuche",
    "WebFetch": "Lädt Seite",
    "Agent": "Subagent",
    "Task": "Subagent",
    "Skill": "Skill",
    "ToolSearch": "Lädt Werkzeuge",
    "Workflow": "Workflow",
    "Artifact": "Artifact",
}


def state_path(session_id):
    safe = "".join(c for c in session_id if c.isalnum() or c in "-_") or "unknown"
    return os.path.join(STATE_DIR, safe + ".json")


def load_state(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def save_state(path, state):
    os.makedirs(STATE_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=STATE_DIR, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False)
    os.replace(tmp, path)


def shorten(text, limit=70):
    text = " ".join(str(text or "").split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def tool_label(name):
    if name in TOOL_LABELS:
        return TOOL_LABELS[name]
    if name.startswith("mcp__"):
        return name.split("__")[-1].replace("_", " ")
    return name


def tool_detail(name, tool_input):
    if not isinstance(tool_input, dict):
        return ""
    if name == "Bash":
        return shorten(tool_input.get("description") or tool_input.get("command"))
    if name in {"Read", "Edit", "MultiEdit", "Write", "NotebookEdit"}:
        return os.path.basename(str(tool_input.get("file_path") or tool_input.get("notebook_path") or ""))
    if name in {"Grep", "Glob"}:
        return shorten(tool_input.get("pattern"))
    if name == "WebSearch":
        return shorten(tool_input.get("query"))
    if name == "WebFetch":
        url = str(tool_input.get("url") or "")
        return url.split("//")[-1].split("/")[0]
    if name in AGENT_TOOLS:
        return shorten(tool_input.get("description"))
    if name == "Skill":
        return shorten(tool_input.get("skill"))
    for key in ("description", "query", "title", "name"):
        if tool_input.get(key):
            return shorten(tool_input[key])
    return ""


def apply_plan(state, name, tool_input):
    """Spiegelt update_plan (Desktop-App) bzw. TodoWrite (CLI) als Aufgabenliste."""
    tasks = state.get("tasks") or []

    if name == "TodoWrite":
        todos = tool_input.get("todos") or []
        state["tasks"] = [
            {"title": shorten(t.get("content"), 80), "status": t.get("status", "pending")}
            for t in todos
            if isinstance(t, dict)
        ]
        return

    items = tool_input.get("items")
    if isinstance(items, list):
        state["tasks"] = [
            {"title": shorten(i.get("content"), 80), "status": i.get("status", "pending")}
            for i in items
            if isinstance(i, dict)
        ]
        return

    if tool_input.get("advance"):
        current = next((i for i, t in enumerate(tasks) if t["status"] == "in_progress"), None)
        if current is not None:
            tasks[current]["status"] = "completed"
        following = next((i for i, t in enumerate(tasks) if t["status"] == "pending"), None)
        if following is not None:
            tasks[following]["status"] = "in_progress"

    for number in tool_input.get("done") or []:
        if isinstance(number, int) and 1 <= number <= len(tasks):
            tasks[number - 1]["status"] = "completed"

    start = tool_input.get("start")
    if isinstance(start, int) and 1 <= start <= len(tasks):
        for task in tasks:
            if task["status"] == "in_progress":
                task["status"] = "pending"
        tasks[start - 1]["status"] = "in_progress"

    state["tasks"] = tasks


def handle(event):
    session_id = str(event.get("session_id") or "")
    if not session_id:
        return
    path = state_path(session_id)
    hook = event.get("hook_event_name")
    now = time.time()

    if hook == "SessionEnd":
        try:
            os.remove(path)
        except OSError:
            pass
        return

    state = load_state(path)
    state["sessionId"] = session_id
    state["project"] = os.path.basename(str(event.get("cwd") or "").rstrip("/")) or "Claude"
    state.setdefault("tasks", [])
    state.setdefault("subagents", 0)

    prompt = str(event.get("prompt") or "").lstrip()
    if hook == "UserPromptSubmit" and prompt.startswith("<"):
        # Systemmeldungen (Hintergrund-Aufgaben, Erinnerungen) setzen die Runde nur fort
        state["status"] = "working"
        state.setdefault("turnStartedAt", now)
        state["currentTool"] = "Denkt nach"
        state["currentDetail"] = ""
    elif hook == "UserPromptSubmit":
        state.update(
            status="working",
            prompt=shorten(event.get("prompt"), 90),
            tasks=[],
            subagents=0,
            agents=[],
            currentTool="Denkt nach",
            currentDetail="",
            turnStartedAt=now,
        )
    elif hook == "PreToolUse":
        name = str(event.get("tool_name") or "")
        tool_input = event.get("tool_input") or {}
        state["status"] = "working"
        state.setdefault("turnStartedAt", now)
        if name in PLAN_TOOLS and isinstance(tool_input, dict):
            apply_plan(state, name, tool_input)
        elif name == "mcp__ccd_turn__wrap_up":
            state["currentTool"] = "Fasst zusammen"
            state["currentDetail"] = ""
        else:
            state["currentTool"] = tool_label(name)
            state["currentDetail"] = tool_detail(name, tool_input)
        if name in AGENT_TOOLS and isinstance(tool_input, dict):
            # Art und Auftrag je Subagent, damit DynamicNotch die passende Figur zeigt
            agents = state.get("agents") or []
            agents.append({
                "type": str(tool_input.get("subagent_type") or "general-purpose"),
                "description": shorten(tool_input.get("description"), 40),
            })
            state["agents"] = agents
            state["subagents"] = len(agents)
    elif hook == "PostToolUse":
        if state.get("status") == "waiting":
            state["status"] = "working"
    elif hook == "SubagentStop":
        agents = state.get("agents") or []
        if agents:
            agents.pop(0)
        state["agents"] = agents
        state["subagents"] = len(agents)
    elif hook == "Notification":
        state["status"] = "waiting"
        state["currentTool"] = "Wartet auf dich"
        state["currentDetail"] = shorten(event.get("message"))
    elif hook == "Stop":
        state["status"] = "done"
        state["subagents"] = 0
        state["agents"] = []
        state["currentTool"] = "Fertig"
        state["currentDetail"] = ""
        for task in state["tasks"]:
            if task["status"] == "in_progress":
                task["status"] = "completed"
    else:
        return

    state["updatedAt"] = now
    save_state(path, state)


def main():
    try:
        handle(json.load(sys.stdin))
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
