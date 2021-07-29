# !addcmd: Add an echo command for this channel

Available to: mods only

Part of manageable feature: commands

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
!!cheer | Any bits are cheered (including anonymously) | The cheerer | bits
!!cheerbadge | A viewer attains a new cheer badge | The cheerer | level
!!raided | Another broadcaster raided you | The raiding broadcaster | viewers
!!channelonline | The channel has recently gone online (started streaming) | The broadcaster | uptime, uptime_hms, uptime_english
!!channelsetup | The channel is online and has recently changed its category/title/tags | The broadcaster | category, title, tag_ids, tag_names
!!channeloffline | The channel has recently gone offline (stopped streaming) | The broadcaster | uptime, uptime_hms, uptime_english
!!musictrack | A track just started playing (see VLC integration) | VLC | desc, blockpath, block, track, playing
!!giveaway_started | A giveaway just opened, and people can buy tickets | The broadcaster | title, duration, duration_hms, duration_english
!!giveaway_ticket | Someone bought ticket(s) in the giveaway | Ticket buyer | title, tickets_bought, tickets_total, tickets_max
!!giveaway_toomany | Ticket purchase attempt failed | Ticket buyer | title, tickets_bought, tickets_total, tickets_max
!!giveaway_closed | The giveaway just closed; people can no longer buy tickets | The broadcaster | title, tickets_total, entries_total
!!giveaway_winner | A giveaway winner has been chosen! | The broadcaster | title, winner_name, winner_tickets, tickets_total, entries_total
!!giveaway_ended | The giveaway is fully concluded and all ticket purchases are nonrefundable. | The broadcaster | title, tickets_total, entries_total, giveaway_cancelled


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
{viewers} | Number of viewers arriving on the raid
{uptime} | Stream broadcast duration - use {uptime|time_hms} or {uptime|time_english} for readable form
{uptime_hms} | (deprecated) Equivalent to {uptime|time_hms}
{uptime_english} | (deprecated) Equivalent to {uptime|time_english}
{category} | English name of the game or category being streamed in
{tag_ids} | Stream tag IDs eg '6ea6bca4-4712-4ab9-a906-e3336a9d8039, e90b5f6e-4c6e-4003-885b-4d0d5adeb580'
{tag_names} | Stream tag names eg '[English], [Family Friendly]'
{track} | Name of the audio file that's currently playing
{block} | Name of the section/album/block of tracks currently playing, if any
{blockpath} | Full path to the current block
{desc} | Human-readable description of what's playing (block and track names)
{playing} | 1 if music is playing, or 0 if paused, stopped, disconnected, etc
{title} | Title of the stream or giveaway (eg the thing that can be won)
{duration} | How long the giveaway will be open (seconds; 0 means open until explicitly closed)
{duration_hms} | (deprecated) Equivalent to {duration|time_hms}
{duration_english} | (deprecated) Equivalent to {duration|time_english}
{tickets_bought} | Number of tickets just bought (or tried to)
{tickets_total} | Total number of tickets bought
{tickets_max} | Maximum number of tickets any single user may purchase
{entries_total} | Total number of unique people who entered
{winner_name} | Name of the person who won - blank if no tickets purchased
{winner_tickets} | Number of tickets the winner had purchased
{giveaway_cancelled} | 1 if the giveaway was cancelled (refunding all tickets), 0 if not (normal ending)


Editing these special commands can also be done via the bot's web browser
configuration pages, where available.

