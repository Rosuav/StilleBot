# !autoban: Keyword-based automatic moderation.

Available to: mods only

Part of manageable feature: allcmds

Usage: `!autoban time badword`

If that word is seen by any non-moderator, and if the bot is a mod in your
channel, then the person will be immediately timed out for the specified
number of seconds, or permanently banned if time is the word 'ban'.

Specify a time of 0 to remove the autoban.

Be very careful of false positives, particularly if banning. If there's any
chance the word would be said legitimately, it's safest to just time the
person out (or purge, which is a one-second timeout).

Note that the word (or phrase) will be recognized case insensitively as a
substring within the person's message. It does not actually have to be a
word per se.

