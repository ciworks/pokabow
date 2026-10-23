class_name ApiConfiguration
extends RefCounted
## Shared, persistent configuration for every service request made by the app.

const SERVER_IP_SETTING_PATH: String = "pokabow/server_ip"
const DEFAULT_SERVER_IP: String = "192.168.0.189"
const API_PORT: int = 3000
const CONFIG_PATH: String = "user://settings.cfg"

static var _server_ip: String = ""


static func server_ip() -> String:
	if not _server_ip.is_empty():
		return _server_ip

	var configured_ip: String = ""
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		configured_ip = String(config.get_value("network", "server_ip", ""))
	if configured_ip.is_empty():
		configured_ip = String(ProjectSettings.get_setting(SERVER_IP_SETTING_PATH, ""))
	if configured_ip.is_empty() or not configured_ip.is_valid_ip_address():
		configured_ip = DEFAULT_SERVER_IP
	_server_ip = configured_ip
	ProjectSettings.set_setting(SERVER_IP_SETTING_PATH, _server_ip)
	return _server_ip


## Validates and persists a server address, then makes it the live app setting.
static func set_server_ip(value: String) -> bool:
	var normalized_ip: String = value.strip_edges()
	if not normalized_ip.is_valid_ip_address():
		return false

	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK and FileAccess.file_exists(CONFIG_PATH):
		return false
	config.set_value("network", "server_ip", normalized_ip)
	if config.save(CONFIG_PATH) != OK:
		return false

	_server_ip = normalized_ip
	ProjectSettings.set_setting(SERVER_IP_SETTING_PATH, _server_ip)
	return true


static func api_base_url() -> String:
	var host: String = server_ip()
	if host.contains(":"):
		host = "[%s]" % host
	return "http://%s:%d" % [host, API_PORT]


static func register_url() -> String:
	return api_base_url() + "/auth/register"


static func login_url() -> String:
	return api_base_url() + "/auth/login"


static func reset_runtime() -> void:
	_server_ip = ""
	var defaults := ConfigFile.new()
	defaults.load("res://project.godot")
	ProjectSettings.set_setting(SERVER_IP_SETTING_PATH, defaults.get_value("pokabow", "server_ip", DEFAULT_SERVER_IP))
