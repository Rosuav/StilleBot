# Commands for $$channel$$

The marker `$$$$` will be replaced with the name of the person entering the
command, and `%s` will take whatever text was added after the command name.

To remove a command or part of a command's output, just blank it.

$$messages$$

Command | Output |
--------|--------|-
$$commands$$
{: #commandview}

[Emotes available to the bot](/emotes)

$$save_or_login$$

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
{: tag=dialog #templates}

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

.iftrue {border-color: #0bb;}
.iffalse {border-color: #a08;}
</style>

> <button type=button class=dialog_cancel>x</button>
>
> Edit command <code id=cmdname></code>
>
> <div id=command_details></div>
>
> <p><button type=button id=save_advanced>Save</button> <button type=button class=dialog_close>Cancel</button></p>
>
{: tag=dialog #advanced_view}
