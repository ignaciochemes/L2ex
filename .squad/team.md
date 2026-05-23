# Squad Team

> l2e — Lineage II Interlude → Elixir/OTP MMO Server

## Coordinator

| Name | Role | Notes |
|------|------|-------|
| Squad | Coordinator | Routes work, enforces handoffs and reviewer gates. |

## Members

| Name | Role | Charter | Status |
|------|------|---------|--------|
| Ripley | 🏗️ Lead Architect | .squad/agents/ripley/charter.md | active |
| Dallas | 🎮 Game Systems Eng. | .squad/agents/dallas/charter.md | active |
| Lambert | 🔌 Network/Protocol Eng. | .squad/agents/lambert/charter.md | active |
| Parker | 🗄️ Persistence Eng. | .squad/agents/parker/charter.md | active |
| Ash | 🧪 Tester/QA | .squad/agents/ash/charter.md | active |
| Scribe | 📋 Session Logger | .squad/agents/scribe/charter.md | active |
| Ralph | 🔄 Work Monitor | .squad/agents/ralph/charter.md | active |
| Bishop | 🏰 Endgame Systems Eng. | .squad/agents/bishop/charter.md | active |

## Project Context

- **Project:** L2E — Lineage II Interlude rebuilt in Elixir/OTP
- **Owner:** Ignacio Gonzalez Chemes
- **Repo:** github.com/ignaciochemes/L2Ex
- **Stack:** Elixir ~> 1.16 / OTP 27, ThousandIsland ~> 1.3, Ecto/PostgreSQL ~> 3.11, Phoenix.PubSub, ETS
- **OS (dev):** Windows — PowerShell only. Never `Add-Content`. Always `replace_string_in_file`.
- **Key constraints:** bcrypt FORBIDDEN → always `pbkdf2_elixir`. No Java porting — L2J Mobius is behavioral reference only.
- **Workspace:** `c:\Users\Ignacio\Desktop\l2e\`
- **Status:** Fase A complete (M1–M42). Next: Fase B (M43–M48).
- **Created:** 2026-05-22
- **Universe:** Alien

## Issue Source

<!-- Update when connecting to GitHub issues -->
- **Repository:** github.com/ignaciochemes/L2Ex
- **Connected:** 2026-05-22
- **Filter:** open issues only
