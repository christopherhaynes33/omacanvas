# Omacanvas

Omacanvas is a native Omarchy Quickshell bar widget for Canvas LMS. It shows
current grades and assignments due soon across active courses in which the
Canvas user has a student enrollment. Teacher-only courses are excluded.

![Omacanvas Overview, Assignments, and Courses views](preview.png)

The panel provides three views:

- **Overview** — assignment counts and current grades.
- **Assignments** — work due during the configured date window.
- **Courses** — per-course grades, assignments, and visibility controls.

## Requirements

- A current Omarchy installation using the standard Quickshell bar.
- Python 3.10 or newer.
- `secret-tool`, provided by the `libsecret` package, for secure token storage.
- A Canvas account permitted to create personal access tokens.

Install the keyring tool if it is not already available:

```sh
omarchy pkg add libsecret
```

## Install

Install directly from the public GitHub repository and enable the widget:

```sh
omarchy plugin add https://github.com/christopherhaynes33/omacanvas.git --enable
```

Choose a bar section when prompted. The default section is the right side.

## Configure Canvas

Omacanvas needs the base URL of the Canvas installation and a personal access
token. The URL is stored in Omarchy's normal widget settings. The token is
stored in the system keyring and is scoped to that URL, so separate Canvas
installations can use separate tokens.

### 1. Find the Canvas base URL

Open Canvas in a browser and copy only the origin from the address bar. Do not
include a course or assignment path.

For example, if a course URL is:

```text
https://canvas.example.edu/courses/12345
```

the base URL is:

```text
https://canvas.example.edu
```

Set it from **Setup → Plugins → Omacanvas**, or from a terminal:

```sh
omarchy bar set io.github.christopherhaynes33.omacanvas baseUrl https://canvas.example.edu
```

### 2. Create a Canvas API token

> [!IMPORTANT]
> Instructure documents manual token generation as a testing workflow and
> requires OAuth for applications used by multiple users. Omacanvas currently
> supports personal access tokens, not OAuth. Before using one, confirm that
> your institution permits a manually generated token for a local, personal
> client. See the [Canvas OAuth2 documentation](https://developerdocs.instructure.com/services/canvas/oauth2/file.oauth).

In Canvas:

1. Open **Account → Settings**.
2. Find **Approved Integrations**.
3. Select **New Access Token**.
4. Enter a purpose such as `Omacanvas` and, if desired, an expiration date.
5. Select **Generate Token**.
6. Copy the token immediately. Canvas normally displays the complete token
   only once.

Some institutions disable personal access tokens. If **New Access Token** is
not available, contact the institution's Canvas administrator.

Treat the token like a password.

### 3. Save the token in the keyring

Run the installed helper and enter the token at the hidden prompt:

```sh
~/.config/omarchy/plugins/io.github.christopherhaynes33.omacanvas/omacanvas set-token \
  --base-url https://canvas.example.edu
```

The URL must match the configured base URL after trailing slashes are removed.
Setting a token again replaces the saved token for that Canvas installation.

Right-click the Omacanvas bar icon after configuration to refresh immediately.

## Use the widget

- Left-click the bar icon to open or close the panel.
- Right-click the bar icon to refresh Canvas data manually.
- Select **Overview**, **Assignments**, or **Courses** at the top of the panel.
- Press `1`, `2`, or `3` to select a view while the panel is focused.
- Press Left/Right to change views and Up/Down to scroll.
- Press `R` or Enter to refresh, and Escape to close the panel.

The widget refreshes every six hours by default and shows assignments due in
the next 14 days.

### Hide or restore a course

In **Courses**, use the eye-slash action to hide the selected course. Hidden
courses are excluded from grades, assignment counts, alerts, and assignment API
requests. Expand the muted hidden-course row and use the eye action to restore
a course.

Course visibility is stored per Canvas installation in:

```text
${XDG_CONFIG_HOME:-~/.config}/omacanvas/hidden-courses.json
```

## Settings

Settings are available under **Setup → Plugins → Omacanvas** or through
`omarchy bar set`:

```sh
# Change the assignment window to 21 days.
omarchy bar set io.github.christopherhaynes33.omacanvas days 21 --json

# Change automatic refresh to every three hours.
omarchy bar set io.github.christopherhaynes33.omacanvas refreshIntervalSec 10800 --json

# Change Canvas installations. Save a token for the new URL separately.
omarchy bar set io.github.christopherhaynes33.omacanvas baseUrl https://other.example.edu
```

The assignment window accepts 1–60 days. The refresh interval accepts
300–86400 seconds.

## Manage API tokens

Replace or add a token:

```sh
~/.config/omarchy/plugins/io.github.christopherhaynes33.omacanvas/omacanvas set-token \
  --base-url https://canvas.example.edu
```

Remove the token for one Canvas installation:

```sh
~/.config/omarchy/plugins/io.github.christopherhaynes33.omacanvas/omacanvas clear-token \
  --base-url https://canvas.example.edu
```

For temporary terminal use, `CANVAS_API_KEY` overrides the keyring without
being written to disk:

```sh
CANVAS_API_KEY='your-token' \
  ~/.config/omarchy/plugins/io.github.christopherhaynes33.omacanvas/omacanvas fetch \
  --base-url https://canvas.example.edu
```

Avoid placing a real token in shell history. Prefer the interactive
`set-token` command for normal use.

## Terminal commands

The helper can also be run independently:

```sh
OMACANVAS=~/.config/omarchy/plugins/io.github.christopherhaynes33.omacanvas/omacanvas

$OMACANVAS fetch --base-url https://canvas.example.edu
$OMACANVAS fetch --json --base-url https://canvas.example.edu
$OMACANVAS set-token --base-url https://canvas.example.edu
$OMACANVAS clear-token --base-url https://canvas.example.edu
$OMACANVAS hide-course COURSE_ID --base-url https://canvas.example.edu \
  --course-name 'Orientation' --course-code 'ORIENT'
$OMACANVAS unhide-course COURSE_ID --base-url https://canvas.example.edu
```

The hide and unhide commands are normally easier to use from the Courses view.

## Update, disable, or remove

Update the Git-managed plugin:

```sh
omarchy plugin update io.github.christopherhaynes33.omacanvas
```

Disable or re-enable the widget:

```sh
omarchy plugin disable io.github.christopherhaynes33.omacanvas
omarchy plugin enable io.github.christopherhaynes33.omacanvas --section right
```

Remove the plugin:

```sh
omarchy plugin remove io.github.christopherhaynes33.omacanvas
```

Removing the plugin does not remove tokens from the system keyring or the
hidden-course preferences. Use `clear-token` before removal and delete the
Omacanvas configuration directory manually if those should also be removed.

## Privacy and permissions

Omacanvas sends authenticated HTTPS requests only to the configured Canvas
installation. It requests active student enrollments, current scores/grades,
and assignments due within the selected window. Hidden courses skip assignment
requests. The token is read from the desktop keyring and is never written to
Omarchy's plain-text configuration.

Like every Omarchy shell plugin, Omacanvas runs as user code inside the shell.
Review third-party plugin source before installation.

## Troubleshooting

- **“Set your Canvas URL”** — configure `baseUrl` using the command above or
  **Setup → Plugins → Omacanvas**.
- **“No Canvas API token is saved”** — run `set-token` with the exact same base
  URL configured for the widget.
- **`secret-tool` is missing** — install `libsecret` with
  `omarchy pkg add libsecret`.
- **Canvas rejected the API token** — create a new token in Canvas and run
  `set-token` again.
- **The API-token option is missing in Canvas** — the institution may prohibit
  personal tokens; ask its Canvas administrator.
- **A course is missing** — Omacanvas intentionally displays only active
  student enrollments. Check the hidden-courses disclosure in the Courses view.
- **Changes do not appear** — right-click the icon, then run
  `omarchy restart shell` if needed.

## Local development

From a checkout of this repository:

```sh
omarchy plugin validate .
python3 -m unittest discover -s tests
omarchy plugin add "$(pwd)" --enable
```

The helper uses only Python's standard library.

## License

Omacanvas is released under the MIT License. See [LICENSE](LICENSE).
