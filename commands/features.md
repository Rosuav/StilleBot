# !features: Enable or disable bot features.

Available to: mods only

Part of manageable feature: features

Usage: `!features featurename {enable|disable|default}`

Setting a feature to 'default' state will enable it if all-cmds, disable if
http-only. TODO: Make this flag visible and possibly mutable.

Note that features disabled here may still be available via the bot's web
interface.

Feature name | Effect
-------------|-------------
quotes | Adding, deleting, and removing quotes
commands | Chat commands for managing chat commands
features | Feature management via chat
debug | Tools for debugging the bot itself
info | General information and status commands


