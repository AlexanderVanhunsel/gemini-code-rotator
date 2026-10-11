# gemini-code-rotator

A small local setup that puts a [LiteLLM](https://github.com/BerriAI/litellm) proxy in front of **several free Google Gemini API keys**, so AI coding agents like [Aider](https://aider.chat) or [Cline](https://cline.bot) keep working when one key hits its free-tier rate limit.

## What it does and why it's useful

The free tier of the Gemini API has strict per-minute and per-day limits. Coding agents send a lot of requests, so with a single key you regularly get `429 Rate Limit` errors in the middle of a session.

This project runs a proxy on `localhost:4000` that holds multiple keys. When one key returns a `429`, the proxy puts it on a short cooldown and retries the request on the next key. Your agent just talks to one OpenAI-compatible endpoint and never notices.

```
 Aider / Cline / any OpenAI-compatible tool
                   │
                   ▼
        LiteLLM proxy (localhost:4000)
        round-robin + retry on 429
          │          │          │
          ▼          ▼          ▼
        key 1      key 2      key 3   ──►  Google Gemini API
```

Good to know:

- It spreads load and survives per-minute limits. It does **not** lift the daily quota of a key; if every key is empty for the day, you wait for the reset.
- Keys only rotate usefully if each one comes from a **separate Google Cloud project** (keys in one project share one quota).
- On the free tier Google may use your prompts to improve its products. Don't send confidential code. Check Google's terms of service before using multiple projects.

## Setup

Tested on Ubuntu (including WSL2 on Windows). macOS with Homebrew should work as well but is untested.

### 1. Prerequisites

**Windows:** this runs inside WSL2 + Ubuntu. In PowerShell:

```powershell
wsl --install -d Ubuntu
```

Restart if asked, then open "Ubuntu" from the Start menu and create a Linux username and password. If the download times out (some campus or company networks block GitHub), try another network such as a phone hotspot for this one step.

**Linux / macOS:** nothing special; you need `git` and `curl`.

**API keys:** create 2–3 keys at <https://aistudio.google.com/apikey>. Choose **"Create API key in new project"** every time.

### 2. Install

Run this inside Ubuntu (clone into your Linux home, not under `/mnt/c`, which is slow):

```bash
cd ~
git clone https://github.com/AlexanderVanhunsel/gemini-code-rotator.git
cd gemini-code-rotator
./install.sh
```

The installer:

- installs `pipx`, **Aider** and **LiteLLM** (with proxy support),
- asks for your API keys (input is hidden) and stores them **only** in the local, git-ignored `.env` (permissions `600`),
- generates a random password for the local proxy,
- generates `litellm_config.yaml` and writes `~/.aider.conf.yml` (an existing one is backed up first).

### 3. Run

Terminal 1 — start the proxy and leave it open:

```bash
cd ~/gemini-code-rotator
./start.sh
```

Wait for `Uvicorn running on http://0.0.0.0:4000`.

Terminal 2 — use Aider in any git project:

```bash
cd ~/my-project      # run `git init` first if it isn't a repo yet
aider
```

Because of `~/.aider.conf.yml`, plain `aider` is enough.

### 4. Verify the key rotation

With the proxy running:

```bash
./check.sh
```

It sends 6 requests in parallel and prints the HTTP status and a short key id per request. You want all `200` and more than one distinct key id. A `retries` value above 0 means the proxy retried a request internally.

## Using it in VS Code (Cline)

1. On Windows, install the **WSL** extension in VS Code.
2. In Ubuntu: `cd ~/my-project && code .` — a new window opens with **WSL: Ubuntu** at the bottom left.
3. In that window, install the **Cline** extension. At the start screen choose **"Bring my own API key"**.
4. Provider settings:

   | Field | Value |
   |---|---|
   | API Provider | `OpenAI Compatible` |
   | Base URL | `http://localhost:4000/v1` |
   | API Key | the value of `LITELLM_MASTER_KEY` in `.env` |
   | Model ID | `gemini-main` |

5. Open **Terminal → New Terminal** in that WSL window, run `./start.sh` from the repo folder and leave it open. Without the proxy you get `ECONNREFUSED 127.0.0.1:4000`.

Any other tool that accepts a custom OpenAI-compatible endpoint (Continue, Roo Code, …) works the same way.

## Everyday use

| Task | How |
|---|---|
| Start | `./start.sh` (keep the terminal open) |
| Stop | `Ctrl+C` in the proxy terminal |
| Replace all keys | `./install.sh --keys`, then restart the proxy |
| Add or change one key | edit `.env` (`GEMINI_API_KEY_4=...`), then restart the proxy |
| Switch model | see below |
| Check rotation | `./check.sh` |

The proxy reads `.env` only at startup, so **always restart it after changing keys or the model**.

### Changing the model

Google retires models regularly. A `404 ... no longer available` error means the model name is outdated. List what your key can use:

```bash
./list-models.sh            # shows models containing "flash"
./list-models.sh pro        # shows models containing "pro"
```

Copy a line (for example `gemini/gemini-3.8-flash`) into `GEMINI_MODEL` in `.env` and restart `./start.sh`. The config file is regenerated on every start.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ECONNREFUSED 127.0.0.1:4000` | The proxy isn't running. Start `./start.sh`. |
| `404 ... no longer available` | Outdated model name. Use `./list-models.sh` and update `GEMINI_MODEL`. |
| `401` / `API key not valid` | A key in `.env` is wrong. Fix it and restart the proxy. |
| Persistent `429` | All keys are rate-limited at once, or they share one Google project. Wait a minute, or add keys from other projects. |
| Slow first response | The model "thinks" before answering; a simple prompt can take ~30 s. |
| `aider: command not found` | Open a new terminal or run `source ~/.bashrc`. |
| `pipx install aider-chat` fails building numpy | Use `./install.sh`; it installs Aider through `aider-install`, which brings a compatible Python. |

## Security

- `.env` holds your real keys and is excluded by `.gitignore`. Never commit it.
- The proxy password (`LITELLM_MASTER_KEY`) is random per install and only protects the local endpoint.
- The proxy listens on all interfaces by default. On shared networks, avoid exposing port 4000 beyond your own machine.

## Files

| File | Purpose |
|---|---|
| `install.sh` | Installs the tools, asks for keys, writes configs |
| `start.sh` | Starts the proxy |
| `generate-config.sh` | Builds `litellm_config.yaml` from `.env` (run by `start.sh`) |
| `check.sh` | Parallel test that shows which key handled each request |
| `list-models.sh` | Lists models available to your key |
| `aider.conf.template.yml` | Template for `~/.aider.conf.yml` |
| `.env.example` | Shape of the `.env` file, with empty placeholders |

## License

[MIT](LICENSE)
