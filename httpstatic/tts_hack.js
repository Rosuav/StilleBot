import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {OPTGROUP, OPTION} = choc; //autoimport

let have_set_voice = false;
export function render(data) {
	set_content("#tts_voice", data.voices.map(([label, voices]) =>
		OPTGROUP({label}, voices.map(v => OPTION({value: v.selector}, v.desc)))
	));
	if (!have_set_voice) {
		have_set_voice = true; //Even if there's nothing in localStorage, only do this once
		const v = localStorage.getItem("ttshack_voice");
		if (v && v !== "") DOM("#tts_voice").value = v;
	}
}

const queue = [];
DOM("#player").onended = e => {
	if (queue.length) {
		e.target.src = queue.shift();
		e.target.play();
	}
};
export function sockmsg_speak(msg) {
	const pl = DOM("#player");
	if (!pl.paused) {
		//There's already something playing. Add this one to the queue.
		queue.push(msg.tts);
	} else {
		//Nothing currently playing. Play this immediately.
		pl.src = msg.tts;
		pl.play();
	}
}

on("submit", "#send", e => {
	e.preventDefault();
	ws_sync.send({cmd: "speak", text: DOM("#stuff").value, voice: DOM("#tts_voice").value});
	DOM("#stuff").value = "";
	localStorage.setItem("ttshack_voice", DOM("#tts_voice").value);
});
