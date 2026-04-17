import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, B, DATE, DIV, FIELDSET, IMG, LEGEND, LI, OPTION, P, SELECT, STYLE, UL} = lindt; //autoimport

//TODO: Sorting
/* Filters at the top (details/summary):
- Clipper
- Year?
- Category
For each filter, show the available options and how many clips in the category; ideally,
also show how many are currently visible, so if you select a clipper, it will show how
many clips each year has within that filter.

Let CathyCat_TV know when it's done-ish, she's excited for it!
*/

//Identify all the things that are relevant to filtering and sorting.
//Each one has an internal ID, a display name, and a fetcher function that gets ID and name for
//a particular clip. Note that the ID may require slugification or similar to ensure it can be
//used in a CSS class.
const filterable = [
	["clipper", "Clipper", clip => [clip.creator_id, clip.creator_name]],
	["year", "Year", clip => [clip.created_at.slice(0, 4), clip.created_at.slice(0, 4)]],
	["category", "Category", clip => [clip.game_id, games[clip.game_id]?.name || "Unknown"]],
];

const filters = Object.fromEntries(filterable.map(fil => [fil[0], ""]));

function GAMETILE(gameid) {
	const game = games[gameid];
	if (!game) return null; //Or should it get a placeholder?
	return DIV({class: "img"}, A({href: "raidfinder?categories=" + encodeURIComponent(game.name)},
		IMG({src: game.box_art_url.replace("{width}", "40").replace("{height}", "54")}),
	));
}

//Build a list of CSS classes representing a clip's filterable attributes
//For each filterable, there will be two attributes, eg "clipper clipper-49497888".
//If an attribute is being filtered for, hide everything with that attribute that doesn't
//also have (one of) the specific one(s) being shown.
function filterclasses(clip) {
	return filterable.map(([fil]) => fil + " " + fil + "-" + clip[fil]).join(" ");
}

function render() {
	const counts = { };
	for (let clip of clips) {
		for (let fil of filterable) {
			const key = fil[0], attr = fil[2](clip);
			clip[key] = attr[0];
			if (!counts[key]) counts[key] = { };
			if (!counts[key][attr[0]]) counts[key][attr[0]] = [1, attr[1]];
			else counts[key][attr[0]][0] += 1;
		}
	}
	replace_content("#display", [
		STYLE(Object.entries(filters).map(([fil, val]) => val === "" ? "" : `.${fil}:not(.${fil}-${val}){display:none}`).join(" ")),
		P(clips.length && filterable.map(([id, name]) => FIELDSET([
			LEGEND("Filter by " + name),
			SELECT({name: id, class: "filter", value: filters[id]}, [
				OPTION({value: ""}, "All (??)"), //FIXME: Get the count (all that would be visible if this filter were removed)
				Object.entries(counts[id])
					.sort((a, b) => b[1][0] - a[1][0]) //Sort the most common ones to the top. TODO: Should this be skipped for Year?
					.map(([key, [count, lbl]]) => OPTION({value: key}, lbl + " (" + count + ")"))
			]),
		]))),
		DIV({class: "streamtiles"}, clips.map(clip => DIV({key: clip.id, class: filterclasses(clip)}, [
			A({href: clip.url}, IMG({
				src: clip.thumbnail_url,
				style: "width: 320px", //Clip thumbnails are larger than we need
			})),
			DIV({className: "inforow"}, [
				//TODO: Put a marker if clip.is_featured
				//TODO: Clip duration somewhere
				UL([
					LI({className: "cliptitle"}, clip.title),
					LI(B(games[clip.game_id]?.name)),
					LI([clip.creator_name, " on ", DATE({datetime: clip.created_at}, new Date(clip.created_at).toLocaleDateString())]),
					LI(clip.view_count + " views"),
				]),
				GAMETILE(clip.game_id),
			]),
		]))),
	]);
}

on("change", "select.filter", e => {
	filters[e.match.name] = e.match.value;
	render();
});

render();
