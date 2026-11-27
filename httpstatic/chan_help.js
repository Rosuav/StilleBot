import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BR} = choc; //autoimport

function get_tips(el) {
	const tips = [];
	let max = el.children.length;
	for (let i = 0; i < max; ++i)
		tips.push(["TIP " + (i+1) + "/" + max + ": ", ...el.children[i].childNodes]);
	//Shuffle the tips. The indices ("TIP 3/42") will be fixed, but the order they're shown is randomized.
	for (let i = 0; i < tips.length; ++i) {
		const j = Math.floor(Math.random() * (tips.length - i)) + i;
		[tips[i], tips[j]] = [tips[j], tips[i]];
	}
	return tips;
}
const tips = get_tips(DOM("#tips"));
let next_tip = 0;

export function render(data) {
	DOM("#is_live").hidden = !data.online;
}

on("submit", "#whisperform", e => {
	e.preventDefault();
	const message = DOM("#whisper").value;
	if (message) ws_sync.send({cmd: "whisper", message});
	DOM("#whisper").value = "";
});

function newtip() {
	set_content("#tip", [
		tips[next_tip++ % tips.length],
		BR(), DOM("#newtip"), //Put that button back where it came from, or so help me, so help me...
	]).hidden = false;
}
on("click", "#newtip", newtip);
newtip(); //Select a tip on startup

//Enable the whisper form only when we're not on the demo channel
if (ws_group != "#0") DOM("#whisperform").hidden = false;
