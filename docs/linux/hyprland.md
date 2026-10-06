# Hyprland physical-display streaming

The Linux compatibility branch supports an active Hyprland Wayland session
started by `ly` through UWSM. The session controller requires
`wayland-session@hyprland.desktop.target`,
`wayland-wm@hyprland.desktop.service`, and `graphical-session.target` to be
active. The user manager must publish `WAYLAND_DISPLAY`, `DISPLAY`, and
`HYPRLAND_INSTANCE_SIGNATURE`.

The machine service captures the existing physical display through KMS.
Virtual displays, Remote Monitor creation, and login-screen streaming are
unavailable in this mode. Physical monitor enumeration in the Web UI is
unavailable; automatic capture or an existing physical output selection is
used. Multiple-monitor offsets and fractional scaling require additional
validation.

Hypridle must provide `org.freedesktop.ScreenSaver` inhibition on the user
bus. The capability-free power helper acquires that inhibitor and wakes the
bound Hyprland instance through `hyprctl`. The broker validates the instance
socket after dropping to the selected user's identity. Hyprland can omit
`XAUTHORITY`; the controller still verifies that its local Xwayland display
is reachable as the session user. Plasma retains its private authority-file
requirement.

## Installation

Use a locally built Arch package containing these compatibility changes.
The release download installer targets the KDE deployment. Configure local
builds with `SUNSHINE_EXECUTABLE_PATH=/usr/bin/vibepollo` and
`SUNSHINE_ASSETS_DIR=share/vibepollo`. The package must include the matching
Linux `libwebrtc.so` when WebRTC is enabled.

Keep the KDE virtual-display pool disabled on a Hyprland-only host before
installing the package:

```bash
sudo systemctl mask vibeshine-vkms.service vibeshine-drm-setup.service
```

The package can install virtual-display driver files, but physical Hyprland
capture does not use them. Unmask these units before switching to the KDE
managed-display deployment.

The package migrates the legacy user profile to `/var/lib/vibepollo` and
enables `vibepollo-session-controller.service`. Retire the old user service
after saving a rollback package and profile backup. Stopping that service
can also terminate applications in its cgroup; preserve unrelated desktop
applications before the transition.

Inspect the replacement with:

```bash
systemctl status vibepollo-session-controller.service vibepollo.service
sudo journalctl -u vibepollo.service -b --no-pager
```

Successful startup requires encoder discovery and a Web UI listener owned
by the current machine host. A client stream is still needed to verify
capture, input, and audio end to end.
