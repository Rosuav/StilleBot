# Followed streams

* Viewers
* Category
* Uptime
{: #sort}

<div id=streams></div>

<style>
#streams {
	display: flex;
	flex-wrap: wrap;
	justify-content: space-around;
}
#streams > div {
	width: 320px; /* the width of the preview image */
}
#streams ul {list-style-type: none; padding: 0;}
#sort {
	display: flex;
	list-style-type: none;
}
#sort li {
	cursor: pointer;
	margin: 0.25em;
	padding: 0.25em;
}
main {max-width: none!important;} /* Override the normal StilleBot style */
</style>

<script>
const follows = $$follows$$
</script>

<script type=module src="/static/raidfinder.js"></script>
