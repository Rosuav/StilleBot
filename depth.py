import json
import glob

def search(path, data):
	if len(path) > 3: print(len(path), "/".join(path), type(data).__name__) # The least-depth nodes aren't a concern
	# Some things are stored as blobs - don't bother recursing into them.
	if len(path) > 2 and path[1] == "commands": return
	if len(path) > 3 and path[1] == "userprefs": return
	# Some might need to be, unsure as yet. Each of these will need to be
	# considered separately - remove them as they're dealt with.
	if len(path) > 2 and path[1] in ("subgiftstats", "raidtrain", "mpn", "variables",
		"raids", "tradingcards", "raidfinder_cache", "private", "errors", "artshare",
		"stream_stats", "affiliate", "voices", "giveaways", "channel_labels"): return
	if len(path) > 3 and path[1] == "raidnotes" and path[3] == "tags": return
	if len(path) > 4 and path[1] == "alertbox" and path[3] in ("replay", "alertconfigs", "files", "ip_log", "personals"): return
	if isinstance(data, list): data = enumerate(data)
	elif isinstance(data, dict): data = data.items()
	else: return
	for key, val in data:
		search(path + (str(key),), val)

for fn in glob.glob("*.json") + glob.glob("channels/*.json"):
	with open(fn, "rb") as f: search((fn,), json.load(f))
