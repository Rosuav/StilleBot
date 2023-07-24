import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, IMG, P} = choc; //autoimport

console.log("Emote data", emotedata);
set_content("#grid", [
	P(["Channel: ", A({href: "https://twitch.tv/" + emotedata.channel}, emotedata.channel)]),
	P(["Emote: ", BR(), IMG({src: "https://static-cdn.jtvnw.net/emoticons/v2/" + emotedata.emoteid + "/static/light/3.0"})]),
]);
