# Manual checks (never run by a suite)

`pam-probe.sh` — does the shipped `pam/password` accept the real password on this machine?
It runs one PAM conversation (`pam-probe.qml`, no
window) against `pam/password` with the shipped config directory — pamtester cannot name
a config directory, and a machine with `/etc/pam.d/h2s-shell-password` never uses the
shipped file otherwise. It asks for the password without echo and passes it through a
private FIFO (never an argument, the environment or a log); one attempt per run.

    tests/manual/pam-probe.sh             # prints Success, Failed or Error

It authenticates against the REAL account: run it once. On anything but Success read the
journal before trying again (`journalctl --since -5min | grep -E 'unix_chkpwd|pam_unix'`):
a `unix_chkpwd … password check failed` line means the password was wrong (the helper ran);
no helper line means it could not be reached. Two attempts at most.
