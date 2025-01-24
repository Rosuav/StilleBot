!["Mustard Mine" banner](/static/MustardMineBanner.png)

# Using the Mustard Mine

Mustard Mine is a Twitch channel bot. This one operates under the name "$$botname$$",
but [the source code](https://github.com/rosuav/stillebot) is available to anyone
who wishes to use it, learn from it, or borrow code from it.

$$yourname$$ $$loglink$$

## For everyone

Mustard Mine uses real-time updates whereever possible. In many cases, status pages and
configuration pages will keep themselves current without your help. If your internet
connection goes down, this may fail, but it should correct itself before long.

## For broadcasters

If the Mustard Mine is serving as your channel bot, a number of configuration pages
are available to you. Want him in your channel? [Activate the bot here!](/activate)
Not sure yet? [Check out the demo pages](/channels/demo/) which let you see everything
that a broadcaster or mod would see!

### Key bot features

#### Chat responses

When the bot is active in a channel, you can create $$link||commands$$, have the bot
$$link||triggers respond to things people say$$, or $$link||specials stream support$$,
and there are various $$link||features chat features$$ that can be quickly enabled
and disabled.

For more details on any of these features, see their individual pages, or go to your
channel's $$link|| landing page$$. $$anon||Note that you will need to log in using the
button above before these features will be available.$$

#### Giveaways

Mustard Mine can manage a $$link||giveaway$$ that your viewers enter using their Twitch
channel points. (This requires partnership or affiliation; if you're neither, there are
other tools which use chat commands to manage giveaways.)

Start by setting everything up - choosing how many points to enter, how many tickets a
single viewer can buy, etc. Then open the giveaway, let people buy tickets, and finally,
pick a winner!

For in-chat notifications, click the "Create Default Notifications" button.
You can then customize the notifications if you wish, but that's entirely optional.

### Features for any streamer

Even if the bot is not directly serving your channel, some tools are available via
the web here.

#### Hype train stats

[Real-time hype train stats](/hypetrain?for=$$chan$$). Get detailed information
on progress, unlockable emotes, etc. Requires broadcaster authentication the first
time, but then can be used by everyone.

This is similar to, but not quite the same as, the in-chat notifications from Twitch.
Notably, it will tell you precisely how many bits to complete the level (not just the
percentage done), and can show *all* the unlockable emotes (not just the one next
tier). Has a mobile-friendlier version for those on-the-go.

#### Channel statistics

Want more information about your channel? Got you covered!

* [Recognizing your top cheerers](/bitsbadges). Who has the highest bits badges in
  your channel? Who has access to your bit emotes?
* [Emote showcase](/emotes?broadcaster=$$chan$$). Show off your glorious emotes in
  large format, tidily organized by how they're unlocked.

#### Raid finder

When you look for some streamer to raid at the end of your own stream, Mustard Mine can
help you [find a suitable target](/raidfinder). Based on factors such as similarity of
viewer count, category, and tags, the bot will organize your follow list into a series
of recommendations. You can then eyeball all the channels, see who you want to raid,
and check if there are any cautionary chat restrictions.

So long as the bot is active in your channel, incoming and outgoing raids will be
recorded, and will be used for recommendations also.

## For moderators and viewers

Moderating a channel managed by Mustard Mine grants you many of the privileges that the
broadcaster has. All of the [key bot features](#key-bot-features) above are available
to you too; the easiest way to access them is to go to the channel's landing page.

A number of the bot's configuration pages can be viewed by anyone, if the broadcaster
is making use of the feature. The easiest way to get the appropriate link is from the
channel itself, either via a link in chat, or the landing page:

Enter a channel name: <input id=for size=20> [Go!](: #gotochannel)

<script>
document.getElementById("gotochannel").onclick = e => window.location.href = "/channels/" + document.getElementById("for").value;
</script>

Non-moderators will often have a read-only view, but moderators usually get full power.

### Raid recommendations

The raid finder can be used by anyone. It will use your own follow list, but can compare
viewership stats to some other broadcaster. FIXME: Explain what does and doesn't change.

### Stream calendar

[Add a streamer's Twitch schedule to your calendar](/calendar) eg Google Calendar or iCal.
This requires no special permissions and can be used for any broadcaster who has set up
an on-Twitch schedule.

Prefer to manage your schedule on Google Calendar and have your Twitch schedule reflect
that? [We can do that too!](/c/calendar) Requires authentication from the broadcaster
and calendar owner, but is then fully automated.

## Bug reports

Found an issue somewhere? Contact Rosuav (the bot author) via Twitch, Discord, or GitHub.
