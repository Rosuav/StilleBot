import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {AUDIO, DIV, FIGCAPTION, FIGURE, IMG, P, SECTION} = choc; //autoimport
import "https://cdn.jsdelivr.net/npm/comfy.js/dist/comfy.min.js"; const ComfyJS = window.ComfyJS;
import {ensure_font} from "$$static||utils.js$$";

const TRANSPARENT_IMAGE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=";
const EMPTY_AUDIO = "data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=";

const alert_formats = {
	text_image_stacked: data => FIGURE({
		className: "text_image_stacked " + (data.layout||""),
		style: `width: ${data.alertwidth||250}px; max-height: ${data.alertheight||250}px;`,
	}, [
		IMG({src: data.image || TRANSPARENT_IMAGE}),
		FIGCAPTION({"data-textformat": data.textformat, style: data.text_css || ""}, data.textformat),
		AUDIO({preload: "auto", src: data.sound, volume: data.volume ** 2}),
	]),
	text_image_overlaid: data => DIV(
		{
			//The layout might be "top_middle", but in CSS, we can handle each dimension
			//separately, so apply classes of "top middle" instead :)
			className: "text_image_overlaid " + (data.layout||"").replace("_", " "),
			style: `background-image: url(${data.image}); width: ${data.alertwidth||250}px; height: ${data.alertheight||250}px;`,
		}, [
			DIV({"data-textformat": data.textformat, style: data.text_css || ""}, data.textformat),
			AUDIO({preload: "auto", src: data.sound || EMPTY_AUDIO, volume: data.volume ** 2}),
		]
	),
};

//Timings:
//1) Alert length is the time that the alert is visible, measured from the
//   start of its fade-in to the start of its fade-out.
//2) Fade-in and fade-out are visual effects only; opacity grows/shrinks
//   over time to smooth things out. Keep these short.
//3) Alert gap is the time after the start of fade-out before another alert
//   will be shown. It should be greater than the fade-out, to avoid ugly
//   "snap back to full" visuals.
//4) An animated alert with a period exactly equal to alert_length + fade-out
//   will run once, then disappear. A period half of that will cycle twice etc.
//5) An audio clip shorter than alert_length + alert_gap will leave silence.
//   Longer than that will skip the audio on stacked alerts. Recommend aiming
//   to keep it roughly as long as the alert, no more, no less.
//6) A long alert_gap will result in weird waiting periods between alerts. A
//   short alert_gap will have alerts coming hard on each other's heels.

let inited = false, token = null;
let hostlist_command = null, hostlist_format = null;
const alert_active = { };
export function render(data) {
	//If, in the future, I need more than one alert type (with distinct formats),
	//replace <main></main> with a set of position-absolute tiles, all on top of
	//each other, each with an ID that says what it is. Alert queueing would be
	//shared across all of them, but each alert type would activate a different
	//element. We guard against playing one audio while another is unpaused.
	//This would then iterate over all of alertconfigs, creating all that are
	//needed; it would need to destroy any that are NOT needed, without flickering
	//those that are still present.
	if (data.alertconfigs) {
		const defaults = data.alertdefaults || { };
		for (let kwd in data.alertconfigs) {
			const cfg = {...defaults, ...data.alertconfigs[kwd]};
			let elem = DOM("#" + kwd);
			if (!elem) elem = DOM("main").appendChild(SECTION({className: "alert", id: kwd})); //New alert type
			if (alert_formats[cfg.format]) set_content(elem, alert_formats[cfg.format](cfg));
			else set_content(elem, P("Unrecognized alert format, check editor or refresh page"));
			alert_active["#" + kwd] = cfg.active;
			elem.dataset.alertlength = cfg.alertlength || 6;
			elem.dataset.alertgap = cfg.alertgap || 1;
			ensure_font(cfg.font);
		}
	}
	if (data.send_alert) do_alert("#" + data.send_alert, data);
	if (data.token && data.token !== token) {
		if (inited) ComfyJS.Disconnect();
		inited = true;
		token = data.token;
		if (token !== "!demo") ComfyJS.Init(ws_group.split("#")[1], data.token);
	}
	if (data.breaknow) {
		//Token has been revoked. This will be the last message we receive
		//on the websocket. Clean up some resources rather than waiting around.
		ComfyJS.Disconnect();
	}
	if (data.hostlist_command) hostlist_command = data.hostlist_command;
	if (data.hostlist_format) hostlist_format = data.hostlist_format;
}

setTimeout(() => {
	if (inited) return; //All good!
	set_content("#hostalert", P("No login token provided - check configuration or refresh page"));
}, 5000);

const alert_queue = [];
let alert_playing = false;

function next_alert() {
	alert_playing = false;
	let next = alert_queue.shift();
	//If you disable an alert while there are a bunch of them queued, they
	//remain in the queue until they would have been displayed, at which
	//point they get dropped. This is unlikely to matter as there's currently
	//no way to see the queue, but if one is ever added, it may be worth
	//hiding any that are inactive.
	while (next && !alert_active[next[0]]) next = alert_queue.shift();
	if (next) do_alert(...next);
}

function remove_alert(alert, gap) {
	DOM(alert).classList.remove("active");
	setTimeout(next_alert, gap * 1000);
}

function do_alert(alert, replacements) {
	if (!replacements.test_alert && !alert_active[alert]) return;
	if (alert_playing) {alert_queue.push([alert, replacements]); return;}
	alert_playing = true;
	const elem = DOM(alert);
	elem.querySelectorAll("[data-textformat]").forEach(el =>
		set_content(el, el.dataset.textformat.replaceAll(/{([^}]+)}/g, (_,kwd) => replacements[kwd] || ""))
	);
	//Force animations to restart
	elem.querySelectorAll("img").forEach(el => el.src = el.src);
	elem.classList.add("active");
	let playing = false;
	//If the page is in the background, don't play audio.
	if (!document.hidden) document.querySelectorAll("audio").forEach(a => {if (!a.paused) playing = true;});
	if (!playing) elem.querySelector("audio").play();
	setTimeout(remove_alert, elem.dataset.alertlength * 1000, alert, elem.dataset.alertgap);
}
window.ping = type => do_alert("#" + (type || "hostalert"), {NAME: "Test", username: "Test", VIEWERS: 42, viewers: 42, test_alert: 1});

const current_hosts = { };
ComfyJS.onHosted = (username, viewers, autohost, extra) => {
	//Note that ComfyJS itself never seems to announce autohosts. It also
	//doesn't provide the displayname, so we fall back on the username.
	if (current_hosts[username]) return;
	current_hosts[username] = 1;
	console.log("HOST:", username, viewers, autohost, extra);
	do_alert("#hostalert", {NAME: username, VIEWERS: viewers, username, viewers});
};

ComfyJS.onCommand = (user, command, message, flags, extra) => {
	if (!hostlist_command || !hostlist_format || command !== hostlist_command) return;
	if (!flags.broadcaster && !flags.mod) return;
	const hosts = Object.keys(current_hosts);
	ComfyJS.Say(hostlist_format.replace("{count}", hosts.length).replace("{hosts}", hosts.join(", ")));
};
