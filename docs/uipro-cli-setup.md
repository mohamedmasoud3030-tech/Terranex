# uipro CLI Setup for Terranex

## 1) Install the CLI globally

```bash
npm install -g uipro-cli
```

## 2) Use this repository

```bash
cd /workspace/Terranex
```

## 3) Initialize for Codex (recommended here)

```bash
uipro init --ai codex
```

## 4) Add your custom instruction template

When prompted for custom instructions, use:

```text
You are Codex, a coding agent based on GPT-5. You and the user share the same workspace and collaborate to achieve the user's goals.

{{ personality }}
```

## Optional: initialize for other assistants

Run any of these if you also want configs for other tools:

```bash
uipro init --ai claude
uipro init --ai cursor
uipro init --ai windsurf
uipro init --ai antigravity
uipro init --ai copilot
uipro init --ai kiro
uipro init --ai qoder
uipro init --ai roocode
uipro init --ai gemini
uipro init --ai trae
uipro init --ai opencode
uipro init --ai continue
uipro init --ai codebuddy
uipro init --ai droid
uipro init --ai kilocode
uipro init --ai warp
uipro init --ai augment
uipro init --ai all
```
