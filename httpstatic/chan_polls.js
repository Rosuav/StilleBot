import {lindt, replace_content, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, LI, TD, TIME, TR, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

function DATE(d) {
	if (!d) return "(unknown)";
	const date = new Date(d * 1000);
	let day = date.getDate();
	switch (day) {
		case 1: case 21: day += "st"; break;
		case 2: case 22: day += "nd"; break;
		case 3: case 23: day += "rd"; break;
		default: day += "th";
	}
	return TIME({datetime: date.toISOString(), title: date.toLocaleString()}, [
		//This abbreviated format assumes English and shows just the date. The hover uses your locale.
		"Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[date.getMonth()] + " " + day,
	]);
}

export function render(data) {
	//TODO: If !data.polls.length, put in a placeholder
	replace_content("#polls tbody", data.polls.map((p, idx) => TR({".polldata": p, "data-idx": idx}, [
		TD(DATE(p.created)), TD(DATE(p.lastused)),
		TD(p.title),
		TD(UL(p.options.split("\n").map(o => LI(o)))),
		TD("TODO"),
		TD(BUTTON({class: "delete"}, "X")),
	])));
}

on("click", "#polls tr[data-idx]", e => {
	const poll = e.match.polldata;
	if (!poll) return;
	const form = DOM("#config").elements;
	form.created.value = poll.created; //TODO: Format with both date and time
	form.lastused.value = poll.lastused; //ditto
	form.title.value = poll.title;
	form.options.value = poll.options;
	//TODO: Results
});

on("submit", "#config", e => {
	e.preventDefault();
	const el = DOM("#config").elements;
	const msg = {cmd: "askpoll"};
	"title options duration".split(" ").forEach(id => msg[id] = el[id].value);
	ws_sync.send(msg);
});

on("click", ".delete", simpleconfirm("Delete this poll?", e => {
	ws_sync.send({cmd: "delpoll", idx: +e.match.closest_data("idx")});
}));
