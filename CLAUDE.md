# chaskiq (fork stufently/chaskiq)

- **Before every push, run the local CI and push only if it is green:** `bin/ci-local`
  (rubocop + rspec in Docker), or let the `.githooks/pre-push` hook run it. Turn the
  hook on with `git config core.hooksPath .githooks` and SSH keepalives with
  `git config core.sshCommand "ssh -o ServerAliveInterval=30"` (GitHub drops an
  idle push connection after ~6-8 min and git then exits SILENTLY, push lost).
  Changed `Dockerfile*` or `.docker-files/` — run the image build BEFORE
  pushing: `bin/ci-local --docker`, then `CI_LOCAL_ARGS=--docker git push` (the
  hook reuses the recorded result; `CI_LOCAL_ARGS` accepts only `--docker`, and a
  result is recorded only for a tree with no untracked files). Without keepalives a hook run over 300 s
  aborts the push even when green: push again. Always check the push output.
- `gh` resolves to upstream chaskiq/chaskiq by default — always pass
  `-R stufently/chaskiq`.
- After pushing, watch the runs until they are green:
  `gh run list -R stufently/chaskiq`, then
  `gh run watch <id> -R stufently/chaskiq --exit-status`.
