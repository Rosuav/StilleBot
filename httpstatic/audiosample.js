import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {AUDIO} = choc; //autoimport
export {render} from "./monitor.js";

const files = [
	"/static/audiosample_gondoliers.ogg",
	"/static/audiosample_iolanthe.ogg",
	"/static/audiosample_mikado.ogg",
	"/static/audiosample_pirates.ogg",
	"/static/audiosample_yeomen.ogg",
];
let current_track = 0;
//Fisher-Yates that thing
for (let i = files.length - 1; i > 0; --i) {
	const j = Math.floor(Math.random() * (i + 1));
	[files[i], files[j]] = [files[j], files[i]];
}
const music = AUDIO({
	controls: true, volume: 0.5,
	src: files[0], id: "music", preload: "auto",
	style: "width: 100%; max-width: 500px; min-width: 300px;",
	onended: e => {music.src = files[++current_track % files.length]; music.play();},
});
set_content("#audio", music);

//Hack the monitor to let us manipulate the time mid-flow (muahahaha)
window.RICEBOT = time => {
	if (time <= 0) {
		if (!music.paused) music.pause();
		return "STOP!";
	} else if (music.paused) music.play();
	return time;
};
