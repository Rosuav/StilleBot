import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, INPUT, LI, TR, TD} = choc;
import {waitlate} from "$$static||utils.js$$";

export const render_parent = DOM("#blocks tbody");
export function render_item(block) {
	return TR({"data-id": block.id}, [
		TD(INPUT({value: block.id, className: "path", size: 80})),
		TD(INPUT({value: block.desc, className: "desc", size: 80})),
		TD([BUTTON({type: "button", className: "save"}, "Save")]),
	]);
}

let curnamehash = null;
export function render(data) {
	if (data.recent) { //Won't be present on narrow updates
		set_content("#nowplaying", data.playing ? "Now playing: " + data.current : "Not playing or integration not active");
		set_content("#recent", data.recent.map(track => LI(track)));
	}
	if (data.curnamehash && data.curnamehash !== curnamehash) {
		//TODO: Only do this if the lyrics details is open, but also do it when you
		//open the details. Or have a separate "keep synchronized" tick box.
		curnamehash = data.curnamehash;
		//Fetch the audio and retain it locally, to allow seeking
		fetch("vlc?raw=audio&hash=" + curnamehash).then(r => r.blob())
			.then(blob => DOM("#karaoke").src = URL.createObjectURL(blob));
		DOM("#karaoke track").src = "vlc?raw=webvtt&hash=" + curnamehash;
	}
}

on("click", "button.save", e => {
	const tr = e.match.closest("tr");
	ws_sync.send({cmd: "update", "id": tr.dataset.id,
		path: tr.querySelector(".path").value,
		desc: tr.querySelector(".desc").value,
	});
});

on("click", "#authreset", waitlate(2000, 10000, "Really reset credentials?", e => ws_sync.send({cmd: "authreset"})));

DOM("#karaoke track").onload = e => {
	if (e.target.readyState < 2) return;
	const cues = [...e.target.track.cues];
	set_content("#lyrics", cues.map(c => {
		const li = LI(c.text);
		c.onenter = () => {li.classList.add("active"); li.scrollIntoView({block: "nearest"});}
		c.onexit = () => li.classList.remove("active");
		return li;
	}));
};
