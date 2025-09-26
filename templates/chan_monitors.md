# Monitors for $$channel$$

<style>
input[type=number] {width: 4em;}
.preview-frame {
	border: 1px solid black;
	padding: 4px;
	max-width: 50em;
	overflow: hidden;
}
.preview-bg {padding: 6px;}
.optionset {display: flex; padding: 0.125em 0;}
.optionset > * {padding: 0.25em; margin-left: 1em;}
.optionset table {border: 1px solid black;}
.optionset tr:last-of-type td {padding-bottom: 0.25em;}
.optionset td {padding: 0.01em 0.25em;}

/* Some controls are irrelevant to Bit Boss monitors */
.is-bitboss .not-boss {display: none;}

#pilethings {
	display: flex;
	overflow-x: scroll;
	max-width: 600px;
	gap: 10px;
}
.pilething {
	min-width: 100px;
	background-color: aliceblue;
	display: flex;
	flex-direction: column;
}
.pilething b {
	margin: 0 auto;
}
.thingpreview {
	width: 80px; height: 80px;
	background-size: contain;
	background-repeat: no-repeat;
}

$$styles$$
</style>

Preview | Actions | Link
--------|---------|------
loading... | - | - 
{:#monitors}

> ### Edit countdown timer
>
> <form method=dialog>
> <div></div>
>
> [Save](: type=submit value=save) [Cancel](: type=submit value=cancel)
> </form>
{: tag=dialog #editcountdown}

<!-- -->

> ### Set countdown time
>
> <label>Target time: <input name=target type=datetime-local></label> [Set counting](:#settarget)
> <label>Countdown: <input name=delay></label> [Set paused](:#setdelay) [Set counting](:#setdelayafter) seconds, mm:ss, or hh:mm:ss
>
> [Close](: type=submit value=cancel)
{: tag=dialog #setcountdowndlg}

[Add text monitor](:.add_monitor data-type=text) [Add goal bar](:.add_monitor data-type=goalbar)
[Add countdown timer](:.add_monitor data-type=countdown) [Add Pile of Pics](:.add_monitor data-type=pile)

> ### Edit text monitor
>
> <form method=dialog>
> <div></div>
>
> [Save](: type=submit value=save) [Cancel](: type=submit value=cancel)
> </form>
{: tag=dialog #edittext}

The text can (and should!) incorporate variables, eg <code>$foo$</code>. Whenever the variable changes, this will update.

> ### Edit goal bar
>
> <form method=dialog>
> <div></div>
>
> [Save](: type=submit value=save) [Cancel](: type=submit value=cancel)
> </form>
{: tag=dialog #editgoalbar}

Note that Piles of Pics may re-drop all objects if the page is refreshed.

> ### Edit pile of pics
>
> <form method=dialog>
> <div></div>
>
> [Save](: type=submit value=save) [Add category](: #addpilecat) [Close](: type=submit value=cancel)
> </form>
{: tag=dialog #editpile}

<!-- -->

> ### Configure thing category
>
> <form method=dialog>
> <div></div>
>
> [Save](: type=submit value=save) [Cancel](: type=submit value=cancel)
> </form>
{: tag=dialog #editthingcat}

<!-- -->

> ### Library
>
> Use PNG or WEBP formats for best results, and keep the files fairly small. Large files
> may cause display issues on first load.
>
> <div id=uploaderror class=hidden></div>
>
> <div id=uploadfrm class=primary><div id=uploads class=filelist></div></div>
> &nbsp;
>
> <label>Upload new file: <input class=fileuploader type=file multiple></label>
> <div class=filedropzone>Or drop files here to upload</div>
>
> &nbsp;
>
> [Select](:#libraryselect disabled=true) [Close](:.dialog_close)
{: tag=dialog #library .resizedlg}

<!-- -->

> ### Rename file
> Renaming a file has no effect on the pile; the name is for your benefit entirely.
>
> <form id=renameform method=dialog>
> <input type=hidden name=id>
> <label>Name: <input name=name size=50></label>
>
> [Apply](:#renamefile type=submit) [Cancel](:.dialog_close)
> </form>
{: tag=dialog #renamefiledlg}
