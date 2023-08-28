import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BUTTON, DIV, FORM, IMG, INPUT, LABEL, LI} = choc; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";
import {update_display, formatters} from "$$static||monitor.js$$";

const goalbar = {
	"barcolor": "#ddddff", "fillcolor": "#663399", "needlesize": 0.375,
	"style": "color: #22aa22;font-weight: bold;font-style: normal;font-size: 24px;font-family: Comfortaa;text-align: center;",
};
function GOALBAR(foll, goal) {
	const mark = foll >= goal ? 100 : foll / goal * 100;
	const background = `linear-gradient(.25turn, ${goalbar.fillcolor} ${mark-goalbar.needlesize}%, red, ${goalbar.barcolor} ${mark+goalbar.needlesize}%, ${goalbar.barcolor})`;
	return DIV({style: goalbar.style + "background: " + background}, foll + "/" + goal);
}

function render_tiles(streamers) {
	return streamers.map(strm => LI([
		A({href: "https://twitch.tv/" + strm.login, target: "_blank"}, B(strm.display_name)),
		A({href: "https://twitch.tv/" + strm.login, target: "_blank"}, IMG({src: strm.profile_image_url, title: "Profile picture", alt: "Streamer avatar"})),
		DIV(["Followers: ", GOALBAR(strm.followers, 50)]),
		editable && BUTTON({class: "remove", "data-id": strm.id}, "Untrack"),
	]));
}

function render(data) {
	set_content("#streamers", [
		render_tiles(data.streamers),
		editable && LI(FORM({id: "newstreamer"}, [
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

on("click", ".remove", simpleconfirm("Are you sure you want to untrack this streamer?", e => {
	fetch("/affiliate?remove=" + e.match.dataset.id)
		.then(r => r.json())
		.then(cfg => render_or_error(cfg));
}));
