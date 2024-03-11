import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV, FIGCAPTION, FIGURE, H2, IMG} = lindt; //autoimport

export function render(data) {
	if (data.emotes) {
		replace_content("#haveemotes",
			"img.have, " +
			data.emotes.map(e => "img[title=\"" + e + "\"]").join(", ") +
			"{filter: saturate(1); border-color: green;}"
		);
		const showcase = DOM("#toggleshowcase");
		if (showcase) set_content(showcase, data.emotes.includes("_allow_showcase") ? "Disable showcase" : "Enable showcase");
	}
	if (data.all_emotes) replace_content("#all_emotes", [
		data.loading && DIV("Loading..."),
		Object.entries(data.all_emotes)
			.sort((a, b) => a[0].localeCompare(b[0]))
			.map(([grp, emotes]) => [
				H2(grp),
				emotes.map(em => FIGURE([
					IMG({
						src: data.template
							.replace("{{id}}", em.id)
							.replace("{{format}}", em.format[em.format.length - 1])
							.replace("{{theme_mode}}", em.theme_mode[0])
							.replace("{{scale}}", em.scale[em.scale.length - 1]),
						alt: em.name, title: em.name,
						class: "have",
					}),
					FIGCAPTION(em.name),
				])),
			]),
	]);
}

on("click", "#toggleshowcase", e => ws_sync.send({cmd: "toggleshowcase"}));
