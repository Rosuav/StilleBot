# !features: Enable or disable bot chat commands.

Available to: mods only

Part of manageable feature: features

Usage: `!features featurename {enable|disable|default}`

Features set to the 'default' state follow the setting for allcmds, so in
general, you need only specify the features that are different from that.

Note that features disabled here may still be available via the bot's web
interface; this governs only the commands available in chat, usually to
moderators.

Feature name | Effect
-------------|-------------
allcmds | Default for features not specified
quotes | Adding, deleting, and removing quotes
commands | Chat commands for managing chat commands
features | Feature management via chat
info | General information and status commands


