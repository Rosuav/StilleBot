const ComfyJS = window.ComfyJS;

export function render(data) {
	document.getElementById("points").innerHTML = data.points + " / " + (data.goal || "1234");
}

if (ComfyJS && window.channelname !== "") {
	ComfyJS.onSub = ComfyJS.onResub = ComfyJS.onSubGift = ComfyJS.onSubMysteryGift = function () {
		ws_sync.send({cmd: "refresh"});
	};
	ComfyJS.Init(window.channelname);
}
