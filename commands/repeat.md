# !repeat: Add a repeated command (autocommand) for this channel

Available to: mods only

Part of manageable feature: commands

Usage: `!repeat minutes text-to-send` or `!repeat minutes !command`

Creates an automated command for this channel. Every N minutes (randomized
a little each way to avoid emitting text in lock-step) while the channel is
live, the text will be sent to the channel, or the command will be run.
The time delay must be at least 5 minutes, but anything less than 20-30 mins
will be too spammy for most channels. Use this feature responsibly.

Commands can also be scheduled at a particular time (interpreted within your
configured time zone). If the channel is live at that time, the command will
be sent.

It's generally best to create autocommands based on [echo commands](addcmd),
as this will allow your mods and/or viewers to access the information directly
rather than waiting for the bot to offer it voluntarily. This also makes any
reconfiguration easy, as the autocommand is simple and easy to type.

Example: `!repeat 60 !uptime` - show the channel's live time roughly every hour

Example: `!repeat 30-60 !twitter` - show your Twitter link every 45 minutes, ish

Example: `!repeat 21:55 !raid` - remind you to go raiding at approx ending time

---

Usage: `!unrepeat text-to-send` or `!unrepeat !command`

Remove an autocommand. The command or text must exactly match something that
was previously set to repeat.

Both of these commands can be used while the channel is offline, but the
automated echoing will happen only while the stream is live.

