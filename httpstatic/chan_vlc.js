import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, INPUT, LI, TR, TD} = choc;
import {waitlate} from "$$static||utils.js$$";

export const render_parent = DOM("#blocks tbody");
export function render_item(block) {
	return TR({"data-id": block.id}, [
		TD(INPUT({value: block.id, class: "path"})),
		TD(INPUT({value: block.desc, class: "desc"})),
		TD([BUTTON({type: "button", class: "save"}, "Save")]),
	]);
}

let curnamehash = null, synckaraoke = false, fetchedaudio = null, last_time_sync = [0, 0];
let remotepause = false;
function set_karaoke_pos() {
	//The time value has two distinct interpretations. Both of them are in
	//microseconds. If data.playing, then data.time is the time_t when the
	//track notionally started; we can subtract it from the current time
	//to get the position within the track, even if there's been a delay.
	//Otherwise, it's the position within the track.
	let msec = last_time_sync[1] / 1000; //JS date uses milliseconds
	if (last_time_sync[0]) msec = +new Date - msec;
	const aud = DOM("#karaoke");
	aud.currentTime = msec / 1000;
	if (last_time_sync[0] && aud.paused) aud.play();
	else if (!last_time_sync[0] && !aud.paused) {remotepause = true; aud.pause();}
}
function fetchkaraoke() {
	//Fetch the audio and retain it locally, to allow seeking
	if (fetchedaudio === curnamehash) return 1;
	fetchedaudio = curnamehash;
	fetch("vlc?raw=audio&hash=" + curnamehash).then(r => r.blob()).then(blob => {
		DOM("#karaoke").src = URL.createObjectURL(blob);
		set_karaoke_pos();
	});
	DOM("#karaoke track").src = "vlc?raw=webvtt&hash=" + curnamehash;
}
export function render(data) {
	if (data.recent) { //Won't be present on narrow updates
		set_content("#nowplaying", data.playing ? "Now playing: " + data.current : "Not playing or integration not active");
		set_content("#recent", data.recent.map(track => LI(track)));
	}
	if (data.curnamehash) {
		curnamehash = data.curnamehash;
		if (synckaraoke) fetchkaraoke();
	}
	if (data.time_usec !== undefined) { //note that it can be zero
		last_time_sync = [data.playing, data.time_usec];
		if (synckaraoke) set_karaoke_pos();
	}
}

//Require the user to click a button to sync karaoke; this avoids autoplay issues,
//even though the audio is actually muted by default.
function set_sync_karaoke(state) {set_content("#karaoke_sync", (synckaraoke = state) ? "Synchronizing!" : "Synchronize");}
on("click", "#karaoke_sync", e => {
	set_sync_karaoke(!synckaraoke);
	if (synckaraoke) {
		fetchkaraoke() && set_karaoke_pos();
		if (e.ctrlKey) {
			document.body.appendChild(DOM("#lyrics"));
			DOM("main").style.display = "none";
			set_content("nav", "Mini-mode enabled, refresh to reset").style.fontSize = "smaller";
		}
	}
});

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

//JavaScript doesn't give us any way to distinguish "you called the pause() method" from
//"the user clicked Pause on the player". So we just set a flag and hope we get the event
//immediately, so that we clear the flag promptly.
DOM("#karaoke").onpause = e => {
	if (remotepause) remotepause = false;
	//Sigh. It turns out, this breaks on a lot of things, like the end of a track.
	//So for now... just don't autodesync. You can manually click the sync button.
	//else set_sync_karaoke(false);
};
