# Commands for $$channel$$

The marker `$$$$` will be replaced with the name of the person entering the
command, and `%s` will take whatever text was added after the command name.

To remove a command or part of a command's output, just blank it.

$$messages$$

Command | Output |
--------|--------|-
$$commands$$

[Emotes available to the bot](/emotes)

$$save_or_login$$

> dialog id=templates
> <button type=button class=dialog_cancel>x</button>
>
> Some handy commands that your channel may want to use:
>
> Command | Text
> --------|------
> $$templates$$
>
> Be sure to customize the command text to suit your channel, lest your commands
> look identical to everyone else's :)

<style>
table {width: 100%;}
th, td {width: 100%;}
th:first-of-type, th:last-of-type, td:first-of-type, td:last-of-type {width: max-content;}
td:nth-of-type(2n+1) {white-space: nowrap;}

#templates tbody tr:nth-child(odd) {
	background: #eef;
	cursor: pointer;
}

#templates tbody tr:nth-child(even) {
	background: #eff;
	cursor: pointer;
}

#templates tbody tr:hover {
	background: #ff0;
}
</style>

> dialog id=options
> <button type=button class=dialog_cancel>x</button>
>
> Set command options for <code id=cmdname></code>
>
> Option      | Effect
> ------------|-----------
> <select id="flg_mode"><option value="">Sequential</option><option value=random>Random</option></select> | Where multiple responses are available, send them all or pick one at random?
> <select id="flg_dest"><option value="">Chat</option><option value="/w $$$$">Whisper</option><option value="/w %s">Whisper to target</option><option value="/web %s">Private access</option></select> | Where should the response be sent?
> <select id="flg_access"><option value="">Anyone</option><option value="mod">Mods only</option></select> | Who should be able to use this command?
> <select id="flg_visibility"><option value="">Visible</option><option value="hidden">Hidden</option></select> | Should the command be listed in !help and the non-mod commands view?
>
> <p><button type=button id=saveopts>Save</button> <button type=button class=dialog_close>Cancel</button></p>
>
