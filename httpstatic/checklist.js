import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const { } = choc;

export function render(data) {
	set_content("#haveemotes",
		"img.have, " +
		data.emotes.map(e => "img[title=\"" + e + "\"]").join(", ") +
		"{filter: saturate(1); border-color: green;}"
	);
	const showcase = DOM("#toggleshowcase");
	if (showcase) set_content(showcase, data.emotes.includes("_allow_showcase") ? "Disable showcase" : "Enable showcase");
}

on("click", "#echolocate", e => ws_sync.send({cmd: "echolocate"}));
on("click", "#toggleshowcase", e => ws_sync.send({cmd: "toggleshowcase"}));
