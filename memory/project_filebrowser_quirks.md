---
name: filebrowser deployment quirks
description: Known issues when deploying filebrowser/filebrowser to Kubernetes — binary path and Viper env var interference
type: project
---

Binary is at `/bin/filebrowser`, not `/filebrowser`.

`FB_USERNAME` and `FB_PASSWORD` env vars are picked up by filebrowser's Viper config system (`SetEnvPrefix("FB")`) in the running server process. Putting them on the main container via `envFrom` breaks authentication.

**Why:** Filebrowser uses Viper with `AutomaticEnv()` and `SetEnvPrefix("FB")`, so any `FB_*` env var silently overrides internal config — corrupting the auth flow even if the database was set up correctly.

**How to apply:** Only mount `filebrowser-env-secret` in the initContainer. The main filebrowser container must NOT have `envFrom` or `env` referencing those credential secrets.
