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
</style>

> ### Edit command <code id=cmdname></code>
> <div id=command_details></div>
>
> [Save](:#save_advanced) [Cancel](:.dialog_close) [Delete?](:#delete_advanced) [Raw view](:#view_raw)
>
{: tag=dialog #advanced_view}
