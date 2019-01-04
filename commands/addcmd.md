# !addcmd: Add an echo command for this channel

Available to: mods only

Usage: `!addcmd !newcommandname text-to-echo`

If the command already exists as an echo command, it will be updated. If it
exists as a global command, the channel-specific echo command will shadow it
(meaning that the global command cannot be accessed in this channel). Please
do not shoot yourself in the foot :)

Echo commands themselves are available to everyone in the channel, and simply
display the text they have been given. The marker `%s` will be replaced with
whatever additional words are given with the command, if any.

Special usage: `!addcmd !!follower text-to-echo-for-new-follower`

Pseudo-commands are not executed in the normal way, but are triggered on
certain events. The `!!follower` pseudo-command happens whenever a person
follows the channel - use `$$` for the person's name.

