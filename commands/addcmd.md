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
!!follower   | Someone follows the channel | The new follower |
!!sub        | Brand new subscription      | The subscriber   | {tier} (1, 2, or 3)
!!resub      | Resub is announced          | The subscriber   | {tier}, {months}
!!subgift    | Someone gives a sub         | The giver        | {tier}, {months}, {recipient}
!!subbomb    | Someone gives many subgifts | The giver        | {tier}, {gifts}
!!cheer      | Bits are cheered            | The giver        | {bits}

