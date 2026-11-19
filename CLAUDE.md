# chaskiq (fork stufently/chaskiq)

- **Before every push, run the local CI and push only if it is green:** `bin/ci-local`
  (rubocop + rspec in Docker), or let the `.githooks/pre-push` hook run it. Turn the
  hook on with `git config core.hooksPath .githooks`. Changed `Dockerfile*` or
  `.docker-files/` — add the image build: `bin/ci-local --docker`
  (`CI_LOCAL_ARGS=--docker git push`).
- `gh` resolves to upstream chaskiq/chaskiq by default — always pass
  `-R stufently/chaskiq`.
- After pushing, watch the runs until they are green:
  `gh run list -R stufently/chaskiq`, then
  `gh run watch <id> -R stufently/chaskiq --exit-status`.
