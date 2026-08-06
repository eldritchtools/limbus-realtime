defmodule LimbusRealtimeWeb.ErrorJSON do
  def render("404.json", _assigns) do
    %{error: "Not Found"}
  end

  def render("500.json", _assigns) do
    %{error: "Internal Server Error"}
  end

  def render(_, _assigns) do
    %{error: "Error"}
  end
end
