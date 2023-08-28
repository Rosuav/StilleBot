import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {B, BUTTON, FORM, IMG, INPUT, LABEL, LI} = choc; //autoimport

function render_tiles(streamers) {
	return streamers.map(strm => LI([
		B(strm.display_name),
		IMG({src: strm.profile_image_url, title: "Profile picture", alt: "Streamer avatar"}),
		//TODO: Goal bar showing strm.followers out of 50
		editable && BUTTON({class: "remove", "data-id": strm.id}, "Untrack"),
	]));
}

function render(data) {
	set_content("#streamers", [
		render_tiles(data.streamers),
		LI(FORM({id: "newstreamer"}, [
			LABEL(["Add a streamer: ", INPUT({autocomplete: "off", size: 20, name: "add"})]),
			BUTTON({type: "submit"}, "Add!"),
		])),
	]);
	if (data.alumni.length) set_content("#alumni", render_tiles(data.alumni));
	else set_content("#alumni", LI("Nobody yet - hang in there!"));
}

render(config);

function render_or_error(data) {
	if (data.error) console.error(data.error); //TODO: Show in DOM
	else render(data);
}

on("submit", "#newstreamer", e => {
	e.preventDefault();
	fetch("/affiliate?" + new URLSearchParams(new FormData(e.match)).toString())
		.then(r => r.json())
		.then(cfg => render_or_error(cfg));
});
