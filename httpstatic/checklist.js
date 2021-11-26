import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {P} = choc;

export function render(data) {
	set_content("#haveemotes",
		"img.have, " +
		data.emotes.map(e => "img[title=\"" + e + "\"]").join(", ") +
		"{filter: saturate(1); border-color: green;}"
	);
}

on("click", "#echolocate", e => ws_sync.send({cmd: "echolocate"}));
