import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV, FIGCAPTION, FIGURE, H1, H2, IMG, INPUT, LI, SECTION, UL} = choc; //autoimport

let now_editing = null;

function TRADING_CARD(info, editmode) {
	if (editmode === 2) {
		now_editing = info;
		DOM("#save").hidden = false;
		return [
			FIGURE([FIGCAPTION("Preview"), TRADING_CARD(info)]),
			FIGURE([FIGCAPTION("Edit"), TRADING_CARD(info, 1)]),
		];
	}
	//TODO: Get the channel background colour to use as the card's colour
	const EDIT = editmode ? (name, value) => INPUT({name, value}) : (n, v) => v;
	return SECTION({class: "card"}, [
		H1(EDIT("card_name", info.card_name)),
		IMG({src: info.image}),
		//Type line might need a rarity marker
		H2(["Streamer — ", EDIT("type", info.type)]),
		DIV({class: "rules"}, [
			UL([
				info.tags.map((t, i) => LI(EDIT("tags:" + i, t))),
				editmode && LI(EDIT("tags:" + info.tags.length, "")),
			]),
			DIV({class: "flavor_text"}, EDIT("flavor_text", info.flavor_text)),
		]),
	]);
}

on("submit", "#pickstrm", async e => {
	e.preventDefault();
	const streamer = e.match.elements.streamer.value;
	if (streamer === "") return;
	const info = await (await fetch("/tradingcards?query=" + encodeURIComponent(streamer))).json();
	console.log(info);
	replace_content("#build_a_card", TRADING_CARD(info.details, 2));
});

on("change", "figure input", e => {
	if (!now_editing) return;
	const parts = e.match.name.split(":");
	//If name is "type", set now_editing["type"] to the value. If it's
	//"tag:5", set now_editing["tag"]["5"] to the value.
	let dest = now_editing;
	for (let i = 0; i < parts.length - 1; ++i) dest = dest[parts[i]];
	dest[parts[parts.length - 1]] = e.match.value;
	replace_content("#build_a_card", TRADING_CARD(now_editing, 2))
});

on("click", "#save", e => {
	fetch("/tradingcards?save", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({info: now_editing}),
	});
});

if (collection) replace_content("#card_collection", collection.map(c => TRADING_CARD(c)));
