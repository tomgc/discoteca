# ============================================================================
# obtener_refresh_token.R — Helper para extraer un refresh token de Spotify
# ============================================================================
#
# Corre ESTO UNA SOLA VEZ localmente para obtener un refresh token que puedas
# usar como GitHub Secret (SPOTIFY_REFRESH_TOKEN) en el workflow programado.
#
# El refresh token de Spotify NO expira mientras no revoques la app desde
# https://www.spotify.com/account/apps. Si lo revocas o cambias secret,
# vuelve a correr este script.
#
# USO:
#   readRenviron(".Renviron")    # carga tus client_id / client_secret
#   source("obtener_refresh_token.R")
# ============================================================================

suppressPackageStartupMessages({
  library(httr2)
  library(cli)
})
source(here::here("utils.R"))

client_id     <- Sys.getenv("SPOTIFY_CLIENT_ID")
client_secret <- Sys.getenv("SPOTIFY_CLIENT_SECRET")

if (client_id == "" || client_secret == "") {
  cli_abort("Falta SPOTIFY_CLIENT_ID o SPOTIFY_CLIENT_SECRET en .Renviron")
}

cliente <- oauth_client(
  id = client_id, secret = client_secret,
  token_url = "https://accounts.spotify.com/api/token",
  name = "discoteca"
)

cli_h1("Spotify — Obtener refresh token")
cli_alert_info("Se abrirá tu navegador para autorizar la app.")

token <- oauth_flow_auth_code(
  client = cliente,
  auth_url = "https://accounts.spotify.com/authorize",
  scope = "user-library-read",
  redirect_uri = SPOTIFY_REDIRECT
)

if (is.null(token$refresh_token) || token$refresh_token == "") {
  cli_alert_danger("No se recibió refresh_token. Revoca la app y vuelve a intentar.")
  cli_alert_info("https://www.spotify.com/account/apps")
} else {
  cli_h2("REFRESH TOKEN — copialo a un lugar seguro AHORA")
  cat("\n", token$refresh_token, "\n\n", sep = "")
  cli_alert_success("Listo. Próximo paso:")
  cli_alert_info("  gh secret set SPOTIFY_REFRESH_TOKEN -R tomgc/discoteca")
  cli_alert_info("  (pegá el token cuando lo pida)")
}
