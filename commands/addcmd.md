# !addcmd: Add an echo command for this channel

Available to: mods only

Usage: `!addcmd !newcommandname text-to-echo`

If the command already exists as an echo command, it will be updated. If it
exists as a global command, the channel-specific echo command will shadow it
(meaning that the global command cannot be accessed in this channel). Please
do not shoot yourself in the foot :)

Echo commands themselves are available to everyone in the channel, and simply
display the text they have been given. The marker `%s` will be replaced with
whatever additional words are given with the command, if any. Similarly, `$$`
is replaced with the username of the person who triggered the command.

Special usage: `!addcmd !!specialaction text-to-echo`

Pseudo-commands are not executed in the normal way, but are triggered on
certain events. The special action must be one of the following:

Special name | When it happens             | Initiator (`$$`) | Other info
-------------|-----------------------------|------------------|-------------
!!subbomb | Someone gives many subgifts | The giver | {tier}, {gifts}
!!follower | Someone follows the channel | The new follower | 
!!cheer | Any bits are cheered (including anonymously) | The giver | {bits}
!!sub | Brand new subscription | The subscriber | {tier} (1, 2, or 3)
!!cheerbadge | A viewer attains a new cheer badge | The cheerer | {level} - badge for N bits
!!resub | Resub is announced | The subscriber | {tier}, {months}, {streak}
!!subgift | Someone gives a sub | The giver | {tier}, {months}, {streak}, {recipient}


Editing these special commands can also be done via the bot's web browser
configuration pages, where available.

