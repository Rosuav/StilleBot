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
!!sub | Someone subscribes for the first time | The subscriber | tier
!!resub | Someone announces a resubscription | The subscriber | tier, months, streak
!!subgift | Someone gives a sub | The giver | tier, months, streak, recipient, multimonth
!!subbomb | Someone gives random subgifts | The giver | tier, gifts
!!cheer | Any bits are cheered (including anonymously) | The giver | bits
!!cheerbadge | A viewer attains a new cheer badge | The cheerer | level
!!channelonline | The channel has recently gone online (started streaming) | The broadcaster | uptime, uptime_hms, uptime_english
!!channeloffline | The channel has recently gone offline (stopped streaming) | The broadcaster | uptime, uptime_hms, uptime_english
!!musictrack | A track just started playing (see VLC integration) | VLC | track


Each special action has its own set of available parameters, which can be
inserted into the message, used in conditionals, etc. They are always enclosed
in braces, and have meanings as follows:

Parameter    | Meaning
-------------|------------------
{tier} | Subscription tier - 1, 2, or 3 (Prime subs show as tier 1)
{months} | Cumulative months of subscription
{streak} | Consecutive months of subscription. If a sub is restarted after a delay, {months} continues, but {streak} resets.
{recipient} | Display name of the gift sub recipient
{multimonth} | Number of consecutive months of subscription given
{gifts} | Number of randomly-assigned gifts. Can be 1.
{bits} | Total number of bits cheered in this message
{level} | New badge level, eg 1000 if the 1K bits badge has just been attained
{uptime} | Number of seconds the stream has been online
{uptime_hms} | Time the stream has been online in hh:mm:ss format
{uptime_english} | Time the stream has been online in words
{track} | Name of the audio file that's just started


Editing these special commands can also be done via the bot's web browser
configuration pages, where available.

