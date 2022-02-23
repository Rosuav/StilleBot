inherit http_websocket;
constant markdown = #"# Alertbox management for channel $$channel$$

<div id=uploads></div>

<style>
#uploads {display: flex;}
</style>
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	/* TODO: If POST request, check if an authorized upload, if so, accept it.
	Authorized uploads are recorded as files, but don't yet have content. An
	attempt to upload into the same ID as an existing file should be rejected.
	On the front end, attempting to upload the same file *name* should offer
	to first delete, but on the back end it will always create new. An upload
	is rejected if the file size exceeds the requested size (even if the new
	file would fit within limits). Upload one item in the group once accepted.
	*/
	//TODO: If key=X set and correct, use group "display"
	//TODO: If key=X set but incorrect, give static error
	//TODO: Require mod login, but give some info if not - since that might be seen if someone messes up the URL
	return render(req, ([
		"vars": (["ws_group": "control", "maxfilesize": 5, "maxtotsize": 25]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	array files = ({ });
	//TODO: Enumerate files in upload order (or upload authorization order)
	return (["items": files,
		//TODO: All details about text positioning and style
	]);
}

void websocket_cmd_upload(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	if (grp != "control" || !conn->is_mod) return;
	if (conn->session->fake) return;
	//TODO: Authorize a file upload.
	//1) Check that the requested size is less than the max
	//2) Check that the user's storage limit isn't reached
	//2a) Enumerate existing files
	//2b) Include previous authorizations (files w/o content)
	//2c) Add the requested size. If total < maxtotsize, okay.
	//3) Generate a unique ID
	//4) Create a file entry for the user with the ID, the name, and the requested
	//   size, but no content file name.
	//5) Update the group.
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//TODO: Delete a file (or file authorization) to free up space.
	//Delete the actual file in httpstatic/uploads, the entry in persist_status,
	//and any other metadata.
}

void websocket_cmd_testalert(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//TODO: Send a test alert. This message comes in on the control connection,
	//and signals everything in the display group.
}
