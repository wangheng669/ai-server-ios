# mac-x Linux preflight runner

`mac-x` performs fast repository checks before an iOS task enters the serialized
central Mac queue. It does not merge `main`, run Xcode, sign the app, or install
to an iPhone.

## Routing

- Runner name: `mac-x-ai-server-ios-preflight`
- Required labels: `self-hosted`, `Linux`, `X64`, `mac-x-preflight`
- Runner directory: `/home/wanngheng/actions-runner/ai_server_ios_preflight`
- User service: `actions-runner-ai-server-ios-preflight.service`
- Workflow job: `Linux preflight on mac-x`
- Status stage: `linux-preflight` through the existing deployment-status API
- Completed delivery status also reports preflight, merge/test, build/install, queue, and total durations for the governance page.

The central Mac job starts only after preflight succeeds. Its own
`ai-merge-to-main` concurrency group remains serialized.

## Install or recover

1. Create a fresh repository registration token for `wangheng669/ai-server-ios`.
2. Install the official GitHub Actions runner in the runner directory.
3. Configure it with the runner name and labels above, using `_work` as its work
   directory.
4. Copy `ci/actions-runner-ai-server-ios-preflight.service` to
   `~/.config/systemd/user/`.
5. Run `systemctl --user daemon-reload` and enable/start the service.
6. Verify the runner is online in GitHub and trigger a `codex/**` branch push.

Registration tokens are short-lived secrets. Never save one in this repository,
the service file, logs, or the governance page.

## Health checks

```bash
systemctl --user status actions-runner-ai-server-ios-preflight.service
journalctl --user -u actions-runner-ai-server-ios-preflight.service -n 100
```

If the runner is reconfigured, stop the service first and use a fresh registration
token. Do not copy `.runner` credentials between repositories or machines.
