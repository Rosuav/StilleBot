# !setcmd: Configure an echo command for this channel

Available to: mods only

Part of manageable feature: commands

Usage: `!setcmd !commandname option [option [option...]]`

Options not specified remain as they are. Newly-created commands have the
first of each group by default.

Group       | Option     | Effect
------------+------------+----------
Multi-text  | sequential | Multiple responses will be given in order as a chained response.
            | random     | Where multiple responses are available, pick one at random.
Destination | chat       | Send the response in the chat channel that the command was given.
            | whisper    | Whisper the response to the person who gave the command.
            | wtarget    | Whisper the response to the target named in the command.
Access      | anyone     | Anyone can use the command
            | modonly    | Only moderators (and broadcaster) may use the command.
            | vipmod     | Only mods/VIPs (and broadcaster) may use the command.
Visibility  | visible    | Command will be listed in !help
            | hidden     | Command will be unlisted

Editing commands can also be done via the bot's web browser configuration
pages, where available.

