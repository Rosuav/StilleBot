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
.optionset fieldset {padding: 0.25em; margin-left: 1em;}
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
> Coming soon: Create and manage the things that get dropped!
>
> <form method=dialog>
> <div></div>
>
> [Save](: type=submit value=save) [Cancel](: type=submit value=cancel)
> </form>
{: tag=dialog #editpile}
