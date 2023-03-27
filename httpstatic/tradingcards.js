import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV, H1, H2, IMG, LI, SECTION, UL} = choc; //autoimport

function TRADING_CARD(info) {
	//TODO: Get the channel background colour to use as the card's colour
	return SECTION({class: "card"}, [
		H1(info.card_name),
		IMG({src: info.image}),
		//Type line might need a rarity marker
		H2(["Streamer — ", info.type]),
		DIV({class: "rules"}, [
			UL(info.tags.map(t => LI(t))),
		]),
	]);
}

on("submit", "#pickstrm", async e => {
	e.preventDefault();
	const streamer = e.match.elements.streamer.value;
	if (streamer === "") return;
	const info = await (await fetch("/tradingcards?query=" + encodeURIComponent(streamer))).json();
	console.log(info);
	replace_content("#build_a_card", TRADING_CARD(info.details));
});
//hack
fetch("/tradingcards?query=devicat").then(r => r.json())
	.then(info => replace_content("#build_a_card", TRADING_CARD(info.details)));

