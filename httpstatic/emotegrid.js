import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, IMG, P, TABLE, TD, TR} = choc; //autoimport

console.log("Emote data", emotedata);
const size = {"1.0": 28, "2.0": 56, "3.0": 112};
function EMOTE(emoteid, scale, alpha) {
	//TODO: Get the emote name for the hover text
	return IMG({
		title: emoteid, alt: "", style:
			"width: " + size[scale] + "px; height: " + size[scale] + "px;"
			+ (alpha === 255 ? "" : "opacity: " + (alpha / 255)),
		src: emote_template
			.replace("{{id}}", emoteid)
			.replace("{{format}}", "static")
			.replace("{{theme_mode}}", "light")
			.replace("{{scale}}", scale),
	});
}

set_content("#grid", [
	P(["Channel: ", A({href: "https://twitch.tv/" + emotedata.channel}, emotedata.channel)]),
	P(["Emote: ", BR(), EMOTE(emotedata.emoteid, "3.0", 255)]),
	TABLE({id: "emotegrid"}, emotedata.matrix.map(row => TR([
		row.map(([emote, alpha]) => TD(EMOTE(emote, "1.0", alpha))),
	]))),
	P([EMOTE(emotedata.emoteid, "3.0", 255)]),
]);
