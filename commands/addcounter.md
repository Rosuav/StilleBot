# !addcounter: Add a counter command for this channel

Available to: mods only

Usage: `!addcounter !newcommandname text-to-echo`

If the command already exists as an echo command, it will be updated. If it
exists as a global command, the channel-specific echo command will shadow it
(meaning that the global command cannot be accessed in this channel). Please
do not shoot yourself in the foot :)

Counter commands themselves are by default available to everyone in the
channel (mods and non-mods alike), and will increment the counter and
display the text they have been given. The marker `%d` will be replaced with
the total number of times the command has been run, and `%s` will be replaced
with any words given after the command (not usually needed). Similarly, `$$`
is replaced with the username of the person who triggered the command.

Mod-only counters, view-only commands, reset commands, and more, can be
managed through the bot's web interface for your channel, or by editing the
bot's commands file.

