extends RefCounted

# Browser file selection is explicit and local. No save or credential is uploaded.
var app: Node
var callback: JavaScriptObject
var browser: JavaScriptObject

func setup(owner_node: Node) -> void:
	app = owner_node
	if not OS.has_feature("web"): return
	browser = JavaScriptBridge.get_interface("BrickBasFiles")
	callback = JavaScriptBridge.create_callback(receive_file)
	if not OS.is_userfs_persistent():
		browser.warn("Browser storage is unavailable. Download a backup before leaving; your build may not survive a reload.")

func choose() -> void:
	if browser != null: browser.choose(callback)

func receive_file(arguments: Array) -> void:
	if arguments.size() != 2: return
	if not String(arguments[1]).is_empty():
		browser.warn(String(arguments[1]))
		return
	# Never reconstruct the scene reentrantly from a browser callback.
	app.import_browser_save.call_deferred(String(arguments[0]))

func download() -> void:
	if app.job != null:
		app.set_status("Career jobs aren't saved part-way: finish the job, or leave it from the job panel.")
		return
	app.capture_save_state()
	JavaScriptBridge.download_buffer(JSON.stringify(app.model.to_dictionary(), "  ").to_utf8_buffer(), "brick-bas-build.json", "application/json")
	app.set_status("Backup downloaded · keep it to restore or move this build")

func saved() -> void:
	JavaScriptBridge.force_fs_sync()
	if OS.is_userfs_persistent():
		app.set_status("Saved in this browser · download a backup before clearing site data")
		if browser != null: browser.requestPersistence()
	else:
		app.set_status("Temporary save only · browser storage unavailable · download a backup")
		if browser != null: browser.warn(app.status_text)
