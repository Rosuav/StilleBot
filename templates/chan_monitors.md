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
.preview div {width: 33%;}
.preview div:nth-of-type(2) {text-align: center;}
.preview div:nth-of-type(3) {text-align: right;}
.optionset {display: flex; padding: 0.125em 0;}
.optionset fieldset {padding: 0.25em; margin-left: 1em;}
</style>

Preview | Actions | Link
--------|---------|------
loading... | - | - 
{:#monitors}

[Add text monitor](:#add_text) [Add goal bar](:#add_goalbar)

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
