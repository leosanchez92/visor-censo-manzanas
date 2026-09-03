library(sf)
library(mapgl)
library(tidyverse)
library(openxlsx)
library(htmltools)
library(htmlwidgets)

# Visualizador simple de variables censales por manzana ------------------------
# Genera un mapa interactivo a partir de la cartografía de manzanas

# Parámetros -------------------------------------------------------------------
comuna_cut     <- 6116                 # CUT de la comuna (6116 = Requínoa)
variable       <- "n_hog_60"           # columna del GPKG a mapear
etiqueta       <- "Hogares compuestos solo por personas de 60 años o más"
n_clases       <- 4                    # nº de clases
cortes         <- NULL                 # NULL = cuantiles automáticos; o un vector, ej. c(1, 3, 6)
paleta_nombre  <- "YlGnBu"             # color paleta RColorBrewer

ruta_manzanas  <- "./INPUT/Cartografia_censo2024_R06.gpkg"
capa_manzanas  <- "Manzanas_CPV24"
dir_salida     <- "./SALIDAS"

if (!dir.exists(dir_salida)) dir.create(dir_salida, recursive = TRUE)

# Carga y filtro ---------------------------------------------------------------
manzanas <- read_sf(ruta_manzanas, layer = capa_manzanas) %>%
  filter(CUT == comuna_cut)

if (!variable %in% names(manzanas)) {
  stop(sprintf("La columna '%s' no existe en la capa. Disponibles: %s",
               variable, paste(names(manzanas), collapse = ", ")))
}

nombre_comuna <- str_to_title(manzanas$COMUNA[1])

# Cortes de la coropleta -------------------------------------------------------
# Por defecto se calculan por cuantiles; se pueden fijar a mano en 'cortes'.
valores <- manzanas[[variable]]

if (is.null(cortes)) {
  q <- quantile(valores, probs = seq(0, 1, length.out = n_clases + 1), na.rm = TRUE)
  cortes <- unique(as.numeric(q))
  cortes <- cortes[-c(1, length(cortes))]        
}

n_col  <- length(cortes) + 1
paleta <- RColorBrewer::brewer.pal(max(3, n_col), paleta_nombre)[seq_len(n_col)]

# Etiquetas de la leyenda a partir de los cortes
leyenda <- c(
  paste0("< ", cortes[1]),
  if (length(cortes) > 1) paste0(cortes[-length(cortes)], " – ", cortes[-1]),
  paste0("≥ ", cortes[length(cortes)])
)

# Mapa interactivo -------------------------------------------------------------
map <- maplibre(style = carto_style("positron")) %>%
  fit_bounds(manzanas) %>%
  add_navigation_control(position = "top-left") %>%
  add_fill_layer(
    id = "manzanas",
    source = manzanas,
    fill_color = step_expr(
      column = variable,
      base   = paleta[1],
      stops  = paleta[-1],
      values = cortes,
      na_color = "white"
    ),
    fill_opacity = 0.8,
    hover_options = list(fill_opacity = 0.2, fill_color = "orange"),
    popup = list(
      "concat",
      "<b>Manzent:</b> ", list("get", "MANZENT"), "<br>",
      "<b>Entidad:</b> ", list("get", "ENTIDAD"), "<br>",
      "<b>", etiqueta, ":</b> ", list("get", variable)
    )
  ) %>%
  add_legend(
    paste0(etiqueta, "<br><span style='font-size:12px;'>Manzanas censales ",
           nombre_comuna, "</span>"),
    values = leyenda,
    colors = paleta,
    type = "categorical",
    position = "bottom-left"
  ) %>%
  add_symbol_layer(
    id = "etiquetas",
    source = manzanas,
    min_zoom = 15,
    text_field = list("get", variable),
    text_size = 12,
    text_color = "black",
    text_halo_color = "white",
    text_halo_width = 2,
    text_allow_overlap = TRUE
  )

# Ocupar toda la ventana al exportar
map <- prependContent(
  map,
  tags$style(HTML("
    html, body, #htmlwidget_container, .htmlwidget {
      margin: 0 !important; padding: 0 !important;
      top: 0 !important; left: 0 !important;
      height: 100vh !important; width: 100vw !important;
      position: absolute !important;
    }
  "))
)

# Exportar ---------------------------------------------------------------------
slug <- paste0(str_to_lower(nombre_comuna), "_", variable)

saveWidget(
  map,
  file = file.path(dir_salida, paste0("mapa_", slug, ".html")),
  selfcontained = TRUE,
  title = paste("Mapa", nombre_comuna, "-", variable)
)

manzanas %>%
  st_drop_geometry() %>%
  write.xlsx(file.path(dir_salida, paste0("tabla_", slug, ".xlsx")))
