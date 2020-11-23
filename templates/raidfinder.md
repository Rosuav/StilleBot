# Followed streams

<button id=highlights>Edit highlight list</button>

* $$sortorders$$
{: #sort}

<div id=streams></div>

> <button type=button class=dialog_cancel>x</button>
>
> <span id=notes_about_channel>Channel name: </span>
>
> <form method=dialog>
> <textarea rows=8 cols=50></textarea>
> <button value="save">Save</button> <button value="cancel">Cancel</button>
> </form>
{: tag=dialog #editnotes}

<a id=yourcat href="#" target="_blank">Current category: ??</a>

> <button type=button class=dialog_cancel>x</button>
>
> Raids to or from this channel:
>
> <ul></ul>
{: tag=dialog #raids}

<style>
#streams {
	display: flex;
	flex-wrap: wrap;
	justify-content: space-around;
}
#streams > div {
	width: 320px; /* the width of the preview image */
	margin-bottom: 1em;
}
#streams ul {list-style-type: none; margin: 0; padding: 0; flex-grow: 1;}
#streams li {
	padding-left: 2em;
	text-indent: -2em;
}
.avatar {max-width: 40px;}
.inforow {display: flex;}
.inforow .img {flex-grow: 0; padding: 0.25em;}
.streamtitle {font-size: 85%;}
.emote {max-height: 1.25em;}
.tag {
	display: inline-block;
	padding: 0 0.125em; text-indent: 0; /* Override the general text-wrap settings from above */
	background: #ddd;
	border: 1px solid black;
	margin-right: 0.5em;
	font-size: 80%;
}

#sort::before {content: "Sort: "; margin: 0.5em 1em 0em -1em;}
#sort {
	display: flex;
	list-style-type: none;
}
#sort li {
	cursor: pointer;
	margin: 0.25em;
	padding: 0.25em;
	text-decoration: solid underline;
}
#sort li.current {text-decoration: double underline;}
.raid-incoming {font-weight: bold;}
.raid-incoming,.raid-outgoing {cursor: pointer;}
.notes {margin-right: 0.5em;}
.notes.absent {filter: grayscale(1);}
main {max-width: none!important;} /* Override the normal StilleBot style */

#raids ul {overflow-y: auto; max-height: 10em;}

.bcasttype {
	background-color: purple;
	color: white;
	border-radius: 50%;
}

.highlighted {
	background-color: #ffc;
	border: 1px solid #ff0;
}
</style>

<script>
const follows = $$follows$$;
const your_stream = $$your_stream$$; //if 0, you're not online
let highlights = $$highlights$$; //human-readable list of highlight channels (even those not online)
const mode = "$$mode||normal$$"; //defines how the follow list is to be interpreted
</script>

<script type=module src="/static/raidfinder.js"></script>
