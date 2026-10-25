# Laptop: Open WebUI for the home Strata servers (chat history, two GPUs in one picker)

Set up **2026-10-25** on the XPS 13. Files: [`assets/open-webui/`](assets/open-webui/).

## Why

[Strata](https://github.com/Niko1221/Strata) serves Qwen3.8-Flash-Next on two machines:
- the RTX 4090 PC: IQ3_XXS, ~50 tok/s;
- the K8's Arc Pro B70: IQ3_S, ~20–25 tok/s ([why slower](k8-plus-egpu.md#strata-local-llm-on-the-b70-and-why-oculink-limits-it)).

Its built-in chat page keeps nothing: a new chat or a reload clears it, by design (the server stores no
conversations). Open WebUI gives saved chats, search and a model picker, with history stored on the laptop.

## Layout

```
browser → Open WebUI 127.0.0.1:3000 ─┬→ 127.0.0.1:8080 ─ssh tunnel→ GPU PC  127.0.0.1:8080 (Strata, 4090)
                                     └→ 127.0.0.1:8081 ─ssh tunnel→ K8      127.0.0.1:8080 (Strata, B70)
```

- Both Strata servers listen on their own localhost only.
- The tunnels and Open WebUI are **user services**, so they start at login and reconnect on their own.
- Open WebUI also binds to `127.0.0.1` only, so nothing is exposed on the LAN.

## Install (no Docker, no root)

Docker on this laptop needs root, so Open WebUI's Python package was installed with uv (run through mise, which
doesn't change mise's config):

```sh
mise exec uv@latest -- uv tool install --python 3.11 open-webui \
  --index https://download.pytorch.org/whl/cpu --index-strategy unsafe-best-match
```

- **The CPU-only PyTorch index keeps it to ~1 GB** instead of a CUDA build of several GB; it installed
  `torch-2.14.1+cpu` and open-webui 0.12.4 in about a minute.
- `--index-strategy unsafe-best-match` is needed: with the default first-index strategy, uv takes `requests` only
  from the PyTorch index, where the version open-webui pins doesn't exist, and the resolve fails.

Then copy the three units to `~/.config/systemd/user/`, replace `<gpu-pc>` / `<k8>` with your SSH aliases, and:

```sh
systemctl --user daemon-reload
systemctl --user enable --now strata-tunnel strata-tunnel-k8 open-webui
```

The first start takes ~1.5 min (database migrations, a small embedding model download).

## Settings that matter (in `open-webui.service`)

| Setting | Why |
|---|---|
| `OPENAI_API_BASE_URLS=…:8080/v1;…:8081/v1`, `OPENAI_API_KEYS=local;local` | one entry per Strata server; Strata accepts any key |
| `ENABLE_PERSISTENT_CONFIG=False` | Open WebUI otherwise copies the env into its database on the first start and ignores later env changes, so adding the second server wouldn't take effect |
| `WEBUI_AUTH=False` | single user, localhost only, no login. Must be set before the first start; it can't be turned off once an account exists |
| `ENABLE_OLLAMA_API=False` | no Ollama here; avoids a failing probe |
| `ANONYMIZED_TELEMETRY=False`, `DO_NOT_TRACK=True`, `SCARF_NO_ANALYTICS=True` | no telemetry |
| `--host 127.0.0.1 --port 3000` | localhost only; 8080 is taken by the first tunnel |

The two Strata servers report different model ids (`qwen3.8-flash-next-iq3_xxs`, `qwen3.8-flash-next-iq3_s`), so
both appear in the picker. Two servers with the same id would collapse into one entry.

## Verification

```sh
systemctl --user is-active strata-tunnel strata-tunnel-k8 open-webui    # active ×3
curl -s http://127.0.0.1:8080/v1/models    # the 4090's model
curl -s http://127.0.0.1:8081/v1/models    # the B70's model
curl -s http://127.0.0.1:3000/api/config   # "auth": false, version 0.12.4
```

Checked 2026-10-25: Open WebUI's `/api/models` (with the token its sign-in returns when auth is off) lists both
models.

When a Strata server is stopped (for example to give the 4090 back to other work), its model disappears from the
picker. Old chats stay.

## Undo

```sh
systemctl --user disable --now open-webui strata-tunnel strata-tunnel-k8
mise exec uv@latest -- uv tool uninstall open-webui
```

Chats and settings live in `~/.local/share/open-webui`; delete it to forget them.
