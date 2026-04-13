import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, B, DATE, DIV, IMG, LI, UL} = choc; //autoimport

//TODO: Sorting
/* Filters at the top (details/summary):
- Clipper
- Year?
- Category
For each filter, show the available options and how many clips in the category; ideally,
also show how many are currently visible, so if you select a clipper, it will show how
many clips each year has within that filter.
*/

function GAMETILE(gameid) {
	const game = games[gameid];
	if (!game) return null; //Or should it get a placeholder?
	return DIV({class: "img"}, A({href: "raidfinder?categories=" + encodeURIComponent(game.name)},
		IMG({src: game.box_art_url.replace("{width}", "40").replace("{height}", "54")}),
	));
}
function render_clip_tiles(clips) {
	set_content("#clips", clips.map(clip => DIV([
		A({href: clip.url}, IMG({
			src: clip.thumbnail_url,
			style: "width: 320px", //Clip thumbnails are larger than we need
		})),
		DIV({className: "inforow"}, [
			//TODO: Put a marker if clip.is_featured
			UL([
				LI({className: "cliptitle"}, clip.title),
				LI(B(games[clip.game_id]?.name)),
				LI([clip.creator_name, " on ", DATE({datetime: clip.created_at}, new Date(clip.created_at).toLocaleDateString())]),
				LI(clip.view_count + " views"),
			]),
			GAMETILE(clip.game_id),
		]),
	])));
}

render_clip_tiles(clips);
