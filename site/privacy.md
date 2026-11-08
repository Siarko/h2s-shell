# Privacy policy

h2s-shell is a desktop shell (panel, notifications, calendar) that runs on your own
computer. This policy covers its Google Calendar integration.

## What it accesses

When you connect a Google account, the shell asks Google for access to your calendars so
it can show, create, edit and delete your events from the panel.

## Where your data goes

- The shell talks to Google's servers directly from your computer. There is no server of
  ours in between, and nothing is sent to the author or to anyone else.
- The sign-in tokens Google issues and the calendar settings you choose are stored only on
  your computer, in the shell's configuration file
  (`~/.config/h2s_shell/config.json`).
- Calendar events are kept in memory while the shell runs, to display them. They are not
  written anywhere else, shared or sold.
- With debug logging turned on in the settings, the shell's log files (on your computer)
  may contain calendar requests and responses.
- The shell has no analytics, telemetry or advertising.

## Removing access

Disconnect the account in the shell's settings, which deletes the stored tokens. You can
also revoke the shell's access at any time at
<https://myaccount.google.com/permissions>.

## Google API Services User Data Policy

The shell's use of information received from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the Limited Use requirements.

## Contact

Questions: open an issue at <https://github.com/Siarko/h2s-shell/issues>.
