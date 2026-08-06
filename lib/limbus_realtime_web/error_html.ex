defmodule LimbusRealtimeWeb.ErrorHTML do
  use Phoenix.Component

  def render("404.html", _assigns), do: "Not Found"
  def render("500.html", _assigns), do: "Internal Server Error"
  def render(_, _assigns), do: "Error"
end
