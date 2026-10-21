#!/bin/sh
BINDIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$BINDIR/ui-common.sh"
sshk_ui_begin "sshk: Connection Setup Help"
while IFS= read -r line; do
    sshk_ui_line "$line"
done <<'HELP'
Kindle -> remote server
1. Create Default Key; export its public key.
2. Connect Kindle to computer by USB.
3. On computer, from the sshk download:
   ./authorize-server.sh user@server
   Add -p PORT for a custom server port.
This installs the Kindle's PUBLIC key there.

Computer -> Kindle
1. Connect Kindle to computer by USB.
2. On computer, from the sshk download:
   ./authorize-kindle.sh /path/to/Kindle
   Uses your computer's public SSH key.
3. Eject USB; run Install / Repair once.
4. SSH Server > Start Server
   Server Status shows the connection command.

Private keys stay on their own device.
HELP
exit 0
