The bot's Demo mode and what it means
=====================================

If a channel called "!demo" exists, it is used as demo mode, but also some
global configuration. Primarily, this allows non-authenticated users to see
all the web configuration pages as though they were a moderator; the system
will pretend that everyone is a mod, but disallow saving. For actual changes
to the demo mode's configs, use "Options | Localhost Mod Override", which
will allow someone logged in as the bot's intrinsic user to be a real mod and
make actual changes.

The Intrinsic User
------------------

Whatever user the bot is authenticated with (Options | Change Twitch User or
Options | Authenticate Manually) is the "intrinsic user". This user account is
the one under which default authentication is done, and will be considered an
admin (see eg Localhost Mod Override). This should be the bot owner.

On the reference deployment, this is Rosuav.

Bot Voices
----------

Any voice authenticated for use under the demo account will be listed on every
channel's voice config page. They will not necessarily be available though. If
logged in as the voice or as the intrinsic user, and if a mod for the channel
in question (or using Localhost Mod Override), the voice can be activated for
that channel.

On the reference deployment, this is Rosuav and MustardMine.

Bot Default Voice
-----------------

The demo channel's selected default voice, if any, is automatically available
to all channels, and is the channel's default voice if none is selected. Each
channel is still welcome to change its description but the voice cannot be
deleted. It will be available in the command editor as "Bot's Own Voice" if it
is not also the channel default.

On the reference deployment, this is MustardMine.
