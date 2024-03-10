import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV} = choc; //autoimport

export function render(data) {
	if (data.emotes) {
		set_content("#haveemotes",
			"img.have, " +
			data.emotes.map(e => "img[title=\"" + e + "\"]").join(", ") +
			"{filter: saturate(1); border-color: green;}"
		);
		const showcase = DOM("#toggleshowcase");
		if (showcase) set_content(showcase, data.emotes.includes("_allow_showcase") ? "Disable showcase" : "Enable showcase");
	}
	if (data.all_emotes) set_content("#all_emotes", [
		data.loading && DIV("Loading..."),
		data.all_emotes.map(grp => [
			//TODO
		]),
	]);
}

on("click", "#echolocate", e => ws_sync.send({cmd: "echolocate"}));
on("click", "#toggleshowcase", e => ws_sync.send({cmd: "toggleshowcase"}));
