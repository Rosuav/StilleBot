# Commands for $$channel$$

The marker `$$$$` will be replaced with the name of the person entering the
command, and `%s` will take whatever text was added after the command name.

To remove a command or part of a command's output, just blank it.

Command | Output |
--------|--------|-
$$commands||- | Loading....$$
{: #commandview}

[Emotes available to the bot](/emotes)

> ### Raw command view
> Copy and paste entire commands in JSON format. Make changes as desired!
> <div class="error" id="raw_error"></div>
> [Compact](:.raw_view .compact) [Pretty-print](:.raw_view .pretty)
> <textarea id=raw_text rows=10 cols=80></textarea><br>
> [Apply changes](:#update_raw) [Close](:.dialog_close)
{: tag=dialog #rawdlg}

$$save_or_login$$

> ### Some handy commands that your channel may want to use:
> > ### Channel info commands
> > Command  | Text
> > ---------|------
> > !discord | Join my Discord server: https://discord.gg/YOUR_URL_HERE
> > !shop    | stephe21LOOT Get some phat lewt at https://www.redbubble.com/people/YOUR_REDBUBBLE_NAME/portfolio iimdprLoot
> > !twitter | Follow my Twitter for updates, notifications, and other whatever-it-is-I-post: https://twitter.com/YOUR_TWITTER_NAME
> > !raid    | Let's go raiding! Copy and paste this raid call and be ready when I host our target! >>> /me twitchRaid YOUR RAID CALL HERE twitchRaid
> > !insta   | My portfolio can be found at https://instagram.com/YOUR_INSTAGRAM_NAME/
> > !calendar | Add my schedule to your calendar: https://calendar.google.com/calendar?cid=LOTS-OF-CHARACTERS
> {: tag=details}
>
> <!-- -->
> > ### Viewer interactivity
> > Command  | Text
> > ---------|------
> > !love    | rosuavLove maayaHeart fxnLove devicatLove devicatHug noobsLove stephe21Heart beauatLOVE hypeHeart
> > !hype    | maayaHype silent5HYPU noobsHype maayaHype silent5HYPU noobsHype maayaHype silent5HYPU noobsHype
> > !hug     | /me devicatHug $$$$ warmly hugs %s maayaHug
> > !loot    | HypeChest RPGPhatLoot Loot ALL THE THINGS!! stephe21LOOT iimdprLoot
> > !lurk    | $$$$ drops into the realm of lurkdom devicatLurk
> > !unlurk  | $$$$ returns from the realm of lurk devicatLurk
> > !save    | rosuavSave How long since you last saved? devicatSave
> > !hydrate | Drink water! Do it! And then do it again in half an hour. (Example timer)
> {: tag=details}
>
> <!-- -->
> > ### Advanced
> > Command  | Text
> > ---------|------
> > !winner  | Congratulations, %s! You have won The Thing, see this link for details...
> > !join    | Join us in Jackbox games! Type !play and go to https://sikorsky.rosuav.com/channels/##CHANNEL##/private
> > !play    | (Private message) We're over here: https://jackbox.tv/#ABCD
> > $$templates$$
> {: tag=details}
>
> Be sure to customize the command text to suit your channel, lest your commands
> look identical to everyone else's :)
{: tag=dialog #templates}

<style>
table {width: 100%;}
th, td {width: 100%;}
th:first-of-type, th:last-of-type, td:first-of-type, td:last-of-type {width: max-content;}
td:nth-of-type(2n+1) {white-space: nowrap;}
</style>

> ### Edit command <code id=cmdname></code>
> <div id=command_details></div>
>
> [Save](:#save_advanced) [Cancel](:.dialog_close) [Delete?](:#delete_advanced) [Raw view](:#view_raw)
>
{: tag=dialog #advanced_view}
