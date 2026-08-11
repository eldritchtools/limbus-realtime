defmodule LimbusRealtimeWeb.SpecialUsers do
  def is_developer(client_id) do
    client_id ==System.get_env("DEVELOPER_USER_ID")
  end
end
