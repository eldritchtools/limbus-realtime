defmodule LimbusRealtimeWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :limbus_realtime

  alias LimbusRealtimeWeb.AllowedOrigins

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_limbus_realtime_key",
    signing_salt: "98YJ/HQU",
    same_site: "Lax"
  ]

  socket "/socket", LimbusRealtimeWeb.UserSocket,
    websocket: [
      check_origin: AllowedOrigins.list()
    ],
    longpoll: false

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  plug CORSPlug,
    origin: AllowedOrigins.list()

  plug LimbusRealtimeWeb.Router
end
