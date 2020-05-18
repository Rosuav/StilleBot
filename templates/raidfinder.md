# Followed streams

* Viewers
* Category
* Uptime
* Raided
{: #sort}

<div id=streams></div>

> dialog id=raids
> <button type=button class=dialog_cancel>x</button>
>
> Raids to or from this channel:
>
> <ul></ul>

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
#sort {
	display: flex;
	list-style-type: none;
}
#sort li {
	cursor: pointer;
	margin: 0.25em;
	padding: 0.25em;
}
.raid-incoming {font-weight: bold;}
.raid-incoming,.raid-outgoing {cursor: pointer;}
main {max-width: none!important;} /* Override the normal StilleBot style */

#raids ul {overflow-y: auto; max-height: 10em;}
</style>

<script>
const follows = $$follows$$
</script>

<script type=module src="/static/raidfinder.js"></script>
