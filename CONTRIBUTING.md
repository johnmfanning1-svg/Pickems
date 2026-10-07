# Contributing

SwiftUI sheets, alerts, and full-screen covers use one presenter per screen.
Read [docs/PRESENTATIONS.md](docs/PRESENTATIONS.md) before adding a modal.

`python3 scripts/check-presentations.py Pickems` must pass. The TestFlight workflow
runs that check immediately after checkout and fails before the archive if it does not.
