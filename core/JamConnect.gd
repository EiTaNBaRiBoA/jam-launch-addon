class_name JamConnect
extends Node
## A [Node] that simplifies integration with the Jam Launch API.
##
## The JamConnect Node serves as an all-in-one Jam Launch integration that
## handles client and server initialization, and provides a session
## establishment GUI for clients. It is designed to be placed in a multiplayer
## game's main scene and connected to the player joining/leaving functions via
## the [signal JamConnect.player_verified] and
## [signal JamConnect.player_disconnected] signals.
## [br][br]
## When a JamConnect node determines that a game is being started as a server
## (e.g. by checking a feature tag), it will add a [JamServer] child node which
## configures the Godot multiplayer peer in server mode and spins up things like
## the Jam Launch Data API (which is only accessible from the server).
## [br][br]
## When a JamConnect node determines that a game is being started as a client,
## it will add a [JamClient] child node which configures the Godot multiplayer
## peer in client mode, and overlays a GUI for establishing the connection to
## the server via the Jam Launch API.
## [br][br]
## The JamConnect Node is not strictly necessary for integrating a game with Jam
## Launch - it is just a reasonable all-in-one default. The various low-level
## clients and utilities being used by JamConnect could be recomposed by an
## advanced user into a highly customized solution.
##

## Emitted in clients whenever the server sends a notification message
signal log_event(msg: String)

## Emitted in the clients whenever the server finishes verifying a connected
## client - [code]pid[/code] is the Godot multiplayer peer ID of the player, and
## the [code]pinfo[/code] dictionary will include the unique Jam Launch username
## of the player in the [code]"name"[/code] key
signal player_verified(pid: int, pinfo: Dictionary)
## Emitted in the clients whenever a player disconnects from the server - see
## [signal JamConnect.player_verified] for argument details.
signal player_disconnected(pid: int, pinfo: Dictionary)

## Emitted in the server immediately before a "READY" notification is provided
## to Jam Launch - this can be used for configuring things before players join.
signal server_pre_ready()
## Emitted in the server immediately after a "READY" notification is provided
## to Jam Launch
signal server_post_ready()
## Emitted in the server before shutting down - this can be used for last minute
## logging or Data API interactions.
signal server_shutting_down()

## Emitted in the server when an asynchronous DB operation has completed or
## errored out
signal game_db_async_result(result, error)
## Emitted in the server when an asynchronous Files operation has completed or
## errored out
signal game_files_async_result(key, error)

## A reference to the child [JamClient] node that will be instantiated when
## running as a client
var client: JamClient
## A reference to the child [JamServer] node that will be instantiated when
## running as a server
var server: JamServer

## The Jam Launch Game ID of this game (a hyphen-separated concatenation of the
## project ID and release ID, e.g. "projectId-releaseId"). Usually derived from
## the [code]deployment.cfg[/code] file located a directory above this file
## which is generated by 
var game_id: String

## The network mode for the client/server interaction as determined by the 
## [code]deployment.cfg[/code] file.
## [br][br]
## [code]"enet"[/code] - uses the [ENetMultiplayerPeer] for connections. This
## provides low-overhead UDP communication, but is not supported by web clients.
## [br]
## [code]"websocket"[/code] - uses the [WebSocketMultiplayerPeer] for
## connections. This enables web browser-based clients.
var network_mode: String = "enet"

## True if a Jam Launch cloud deployment for this project is known to exist via
## the presence of a [code]deployment.cfg[/code] file. When this value is false,
## only local testing functionality can be provided.
var has_deployment: bool = false

func _init():
	print("Creating game node...")
	
	var dir := (self.get_script() as Script).get_path().get_base_dir()
	var deployment_info = ConfigFile.new()
	var err = deployment_info.load(dir + "/../deployment.cfg")
	if err != OK:
		print("Game deployment settings could not be located - only the local hosting features will be available...")
		game_id = "init-undeployed"
	else:
		game_id = deployment_info.get_value("game", "id")
		network_mode = deployment_info.get_value("game", "network_mode", "enet")
		has_deployment = true

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# force quit after a timeout in case graceful shutdown blocks up
		await get_tree().create_timer(4.0).timeout
		get_tree().quit(1)

func _ready():
	print("JamConnect node ready, deferring auto start-up...")
	start_up.call_deferred()

## Start the JamConnect functionality including client/server determination and 
## multiplayer peer creation and configuration.
func start_up():
	print("Running JamConnect start-up...")
	get_tree().set_auto_accept_quit(false)
	
	var args := {}
	for a in OS.get_cmdline_args():
		if a.find("=") > -1:
			var key_value = a.split("=")
			args[key_value[0].lstrip("--")] = key_value[1]
		elif a.begins_with("--"):
			args[a.lstrip("--")] = true
	
	if OS.has_feature("server") or "--server" in OS.get_cmdline_args():
		server = JamServer.new()
		add_child(server)
		server.server_start(args)
	else:
		client = JamClient.new()
		add_child(client)
		client.client_start()

## A client-callable RPC method used by connected to clients to verify their
## identity to the server with a join token.
@rpc("any_peer", "call_remote", "reliable")
func verify_player(join_token: String):
	if multiplayer.is_server():
		server.verify_player(join_token)

## A server-callable RPC method for broadcasting informational server messages
## to clients
@rpc("reliable")
func notify_players(msg: String):
	log_event.emit(msg)

## A method that can be called on the server in order to make sure the client
## is verified before relaying to other clients.
func server_relay(callable: Callable, args: Array = []):
	if not multiplayer.is_server():
		return
	server.rpc_relay(callable, multiplayer.get_remote_sender_id(), args)

## Converts this JamConnect node from being configured as a client to being
## being configured as a server in "dev" mode. Used for simplified local hosting
## in debug instances launched from the Godot editor.
func start_as_dev_server():
	client.queue_free()
	client = null

	server = JamServer.new()
	add_child(server)
	server.server_start({"dev": true})

## Gets the project ID (the game ID without the release string)
func get_project_id() -> String:
	return game_id.split("-")[0]

## Gets the release ID (a.k.a. game ID - the project ID concatenated with the
## release string
func get_release_id() -> String:
	return game_id

## Gets the session ID (the game ID concatenated with a unique session string)
func get_session_id() -> String:
	if server:
		return OS.get_environment("SESSION_ID")
	elif client:
		return client.session_id
	else:
		return ""
