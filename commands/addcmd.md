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
!!follower | Someone follows the channel | The new follower | 
!!sub | Brand new subscription | The subscriber | tier
!!resub | Resub is announced | The subscriber | tier, months, streak
!!subgift | Someone gives a sub | The giver | tier, months, streak, recipient, multimonth
!!subbomb | Someone gives many subgifts | The giver | tier, gifts
!!cheer | Any bits are cheered (including anonymously) | The giver | bits
!!cheerbadge | A viewer attains a new cheer badge | The cheerer | level


Each special action has its own set of available parameters, which can be
inserted into the message, used in conditionals, etc. They are always enclosed
in braces, and have meanings as follows:

Parameter    | Meaning
-------------|------------------
{tier} | Subscription tier - 1, 2, or 3 (Prime subs show as tier 1)
{months} | Cumulative months of subscription
{streak} | Consecutive months of subscription. If a sub is restarted after a delay, {months} continues, {streak} resets.
{recipient} | Display name of the gift sub recipient
{multimonth} | Number of consecutive months of subscription given
{gifts} | Number of randomly-assigned gifts. Can be 1.
{bits} | Total number of bits cheered in this message
{level} | New badge level, eg 1000 if the 1K bits badge has just been attained


Editing these special commands can also be done via the bot's web browser
configuration pages, where available.

