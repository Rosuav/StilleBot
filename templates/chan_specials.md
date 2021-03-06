# Special triggers for $$channel$$

When certain events happen, StilleBot can automatically react, to thank a
person or celebrate an activity etc. Every event is triggered by somebody -
the initiator of the special action - and many events have additional information
available. For example, when someone [cheers](https://help.twitch.tv/s/article/guide-to-cheering-with-bits)
in your channel, StilleBot can thank the person with a message such as:

<pre>Thank you for the {bits} bits, $$$$!

MustardMine: This is a test cheer cheer100
StilleBot: Thank you for the 100 bits, MustardMine!
</pre>

To respond to the contents of regular messages, see [Triggers](triggers).

Channel moderators may add and edit these responses below.

<div id=tabset></div>

Special&nbsp;name | Response | -
------------------|----------|----
-                 | $$loadingmsg$$
{: #commands}

<p></p>

$$save_or_login$$

> ### Edit special response <code id=cmdname></code>
> <ul id=parameters></ul>
> <div id=command_details></div>
>
> [Save](:#save_advanced) [Cancel](:.dialog_close) [Delete?](:#delete_advanced) [Raw view](:#view_raw)
>
{: tag=dialog #advanced_view}

<style>
table {width: 100%;}
th, td {width: 100%;}
th:first-of-type, th:last-of-type, td:first-of-type, td:last-of-type {width: max-content;}
td:nth-of-type(2n+1):not([colspan]) {white-space: nowrap;}
.gap {height: 1em; background: inherit;}
td ul {margin: 0;}

#tabset {display: flex;}
.tabradio {display: none;}
.tablabel {
	display: inline-block;
	cursor: pointer;
	padding: 0.4em;
	margin: 0 1px;
	font-weight: bold;
	border: 1px solid black;
	border-radius: 0.5em 0.5em 0 0;
	height: 2em; width: 8em;
	text-align: center;
}
tr[data-tabid] {display: none; background: #e1e1e1;}
.tabradio:checked + label {background: #efd;}
</style>

> ### Raw command view
> Copy and paste entire commands in JSON format. Make changes as desired!
> <div class="error" id="raw_error"></div>
> [Compact](:.raw_view .compact) [Pretty-print](:.raw_view .pretty)
> <textarea id=raw_text rows=10 cols=80></textarea><br>
> [Apply changes](:#update_raw) [Close](:.dialog_close)
{: tag=dialog #rawdlg}
