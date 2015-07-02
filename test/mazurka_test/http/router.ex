defmodule MazurkaTest.Router do
  use Mazurka.Protocol.HTTP.Router
  alias MazurkaTest.Resources

  plug :match
  plug :dispatch

  get     "/",        Resources.Root
  get     "/users/:user",   Resources.Users
end