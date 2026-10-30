# Vokop

Independent OpenWrt routing application based on [Forkop](https://github.com/ushan0v/forkop), itself derived from [Podkop](https://github.com/itdoginfo/podkop).

Vokop retains the upstream routing and subscriptions interfaces and adds its own versioned integration for the owner’s 3x-ui panel. Implementation and hardware verification are in progress; this checkout is not a tested router release.

- Original upstream README: [docs/upstream/Forkop-README.md](docs/upstream/Forkop-README.md).
- Upstream base commit: `dd483297be0ac4e52bb8f482e2640238b75af532`.
- Original GPL license and copyright notices are retained.
- No affiliation with or endorsement by upstream authors is implied.

Installation does not opt the router into routing changes: `vokop.settings.enabled` defaults to `0`. Review configuration and recovery instructions before enabling it locally in LuCI.

The project repository is https://github.com/remzone/vokop. No release-update source is enabled by default. The installer requires explicit `VOKOP_REPO_OWNER` and `VOKOP_REPO_NAME`; do not use upstream Forkop binaries as Vokop packages. The runtime release updater is disabled until `VOKOP_RELEASE_REPO` is configured in the local service environment.
