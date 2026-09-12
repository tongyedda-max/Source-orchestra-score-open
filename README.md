# Source-orchestra-score-open

# 🎼 Orchestra Stand

A free digital music stand for amateur orchestras and school ensembles.
Put your sheet music in the cloud, share one link, and every member reads on
their phone, tablet, or laptop. Section leaders draw bowings right on the
score — everyone sees them instantly. One person turns pages, everyone follows.

**Open source (non-commercial) · Free backend (Supabase) · Free hosting
(GitHub Pages) · no monthly cost**

---

## Features

| Feature | Description |
|---|---|
| Gate password | One shared password for the whole orchestra; devices remember it |
| Three roles | Member (read-only) · Section Leader (max 2 concurrent editors) · Chief/Librarian (full control) |
| Score library | Folder hierarchy: upload PDFs, rename, cut/copy/paste, delete |
| Reader | Tap-to-turn, swipe, arrow keys, pinch-zoom 1–5x, fullscreen |
| Bowing marks | Pen, highlighter, dashed mode, straight lines, Pi/V bow stamps, tap-erase, text notes; 6 colors; 0.5–12px width; finger, stylus and mouse all draw with identical width |
| Stylus support | Hold the S Pen barrel button = instant erase, release restores your tool; palm rejection while writing |
| Undo system | Undo last stroke; page clears (strokes + texts) restorable within 30 seconds |
| Broadcast | Master turns pages, everyone follows in real time; LIVE badge; jump-to-master button |
| Layer compare | Overlay a same-page-count PDF on the score with adjustable opacity |
| Notice board | Tab next to the library; leaders/chief post, pin, edit, delete; syncs live |
| Print/Export | Content (bowings+text / bowings / text / clean) × range (page / whole) |
| Bilingual UI | 繁體中文 / English |

---

## How to Use

| Role | Activate | Can do |
|---|---|---|
| Member | Enter the gate password | View scores and notices; follow broadcast; view layers |
| Section Leader | Role menu → Become Leader → edit password | + draw bowings/text/layers on any score; first claimer is broadcast master |
| Chief | Role menu → Become Chief → librarian password | + file manager, erase anyone's marks, clear whole page (strokes+texts), system admin |

Typical rehearsal: Chief uploads PDFs → Leaders draw bowings → Leader
broadcasts the score → everyone follows the master's page turns → Chief clears
the page afterwards (undo within 30s if needed).

---

## Build Your Own (about 20 minutes)

You need two free accounts: GitHub and Supabase.
The repo ships three files: index.html (the app), setup.sql (the database),
and prompt.txt (an AI prompt to regenerate or modify the app).

### Step 1 — Create a Supabase project

1. Go to supabase.com, sign up, create a New project.
2. Pick a region near you (for example Singapore).
3. In Project Settings → API, copy the Project URL and the anon/publishable key.

### Step 2 — Run the database SQL

1. Open the setup.sql file in this repo and copy its ENTIRE contents.
2. In Supabase, open SQL Editor → New query → paste → Run.
3. The script is idempotent: safe to re-run, never destroys data.
4. It creates all tables, RLS policies, realtime publication, storage bucket,
   and 35 password-checked RPC functions.

Default passwords after setup: gate-1234 / edit-1234 / admin-1234 —
CHANGE THEM in Step 4.

### Step 3 — Deploy the app

1. Create a GitHub repo and put index.html in the repo root.
2. Edit the top of index.html and set your own keys:

    const SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
    const SUPABASE_KEY = 'YOUR-ANON-KEY';

3. Repo Settings → Pages → Deploy from a branch → main / root → Save.
4. Your site goes live at https://YOUR-USERNAME.github.io/YOUR-REPO/

### Step 4 — Change the passwords NOW

1. Open your site, enter the gate password gate-1234.
2. Role menu → Become Chief → enter admin-1234.
3. Library page → System Admin → change all three passwords to your own.

### Step 5 — Invite your orchestra

Share the URL plus the gate password in your group chat. Done.

---

## Regenerate or Modify with AI

The file prompt.txt in this repo contains a complete, copy-paste prompt that
makes any AI assistant (Claude, ChatGPT, Gemini, and so on) generate this
entire system from scratch — SQL plus single-file app — or modify this one.

Tips:
- Paste the whole prompt in one message.
- If the output gets truncated, reply: continue exactly where you stopped,
  no repetition — and it will resume.
- Always run the produced SQL in a fresh Supabase project first.

---

## Architecture

    GitHub Pages (static index.html)  <---HTTPS--->  Supabase
    - pdf.js renders PDFs                           - Postgres + RLS + RPCs
    - Canvas annotation layer                       - Realtime live sync
    - No build step                                 - Storage (PDF files)

Why password-based roles instead of user accounts? Orchestras are small and
trust-based. Three shared passwords keep the UX frictionless — no sign-ups,
works instantly on any device — while every write goes through a SECURITY
DEFINER RPC that validates the password server-side, and RLS keeps every table
read-only to the public.

---

## Security Notes

- The anon key in index.html is public by design; security comes from RLS plus
  password-checked RPCs, not from hiding the key.
- Change all three passwords immediately after setup.
- Never put a password in your display name (the app blocks names containing
  a password).
- The PDF bucket is publicly readable by URL; the gate protects the app UI,
  not direct file URLs. Upload only material you have the rights to share.

---

## License — Open Source, Non-Commercial

This project is open source and free for the community under the
**Orchestra Stand Non-Commercial License v1.0** (in the spirit of
PolyForm Noncommercial 1.0.0, https://polyformproject.org/licenses/noncommercial/1.0.0/): https://github.com/tongyedda-max/orchestra-score/tree/Open-source

- You MAY freely use, copy, modify, merge, and redistribute this project for
  any NON-COMMERCIAL purpose — your orchestra, school, community ensemble,
  personal study, teaching, or a fork for your own group.
- Modifications and forks are welcome and encouraged. Keep this license notice
  and credit in your copy.
- COMMERCIAL USE IS PROHIBITED. You may not sell this software, offer it as a
  paid hosted service, bundle it into a paid product or subscription, or
  otherwise use it to generate revenue, directly or indirectly.
- Attribution appreciated: a link back to this repository in your fork's
  README is enough.

Short version: share it, remix it, use it with your ensemble — just do not
charge money for it.

Copyright (c) 2026 — released for the community orchestra movement.-https://github.com/tongyedda-max/orchestra-score/tree/Open-source
