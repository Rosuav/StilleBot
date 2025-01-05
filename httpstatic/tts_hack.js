import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {OPTGROUP, OPTION} = choc; //autoimport

export function render(data) {
	set_content("#tts_voice", data.voices.map(([label, voices]) =>
		OPTGROUP({label}, voices.map(v => OPTION({value: v.selector}, v.desc)))
	));
}

export function sockmsg_speak(msg) {
	DOM("#player").src = msg.tts;
	DOM("#player").play();
}

on("submit", "#send", e => {
	e.preventDefault();
	ws_sync.send({cmd: "speak", text: DOM("#stuff").value, voice: DOM("#tts_voice").value});
});
