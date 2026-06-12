# iOS Maestro flows

Non-regression checks for the Hotwire Native iOS shell. Flows run against a
booted simulator with the **debug** build of `fr.armandmgt.velo` already
installed (the `mise run debug` task takes care of that).

## Run one flow

```sh
cd native/ios
maestro test maestro/auth_modal.yaml
```

## Run them all

```sh
maestro test maestro
```

## Prereqs

- A simulator booted: `cd native/ios && mise run simulator`.
- The Velo Debug app installed on it: `mise run debug` once.
- Rails dev server running (`bin/dev`) so `localhost:3000` is reachable; the
  default dev user is `test@example.com` / `dev` (seeded by `db/seeds.rb`).

## Flows

- `auth_flow.yaml` — Cold-launches the app with state cleared, asserts the
  unauthenticated root navigator is showing the login page **and no tab bar**,
  signs in, and verifies the tab-bar root takes over with both tabs working.
- `auth_logout.yaml` — Signs in, opens the top-bar overflow, taps Se
  déconnecter, and verifies the tab bar is gone and we're back on the login
  page. Exercises the `is_after_sign_out_path` path-property hand-off that
  swaps the window root back to the unauthenticated navigator.
