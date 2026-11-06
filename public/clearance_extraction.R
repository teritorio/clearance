# Extraction de données depuis Clearance (API Overpass-like)
# https://app.clearance.teritorio.xyz

paquets <- c("httr2", "sf", "dplyr", "writexl")
paquets_manquants <- paquets[!paquets %in% installed.packages()[, "Package"]]
if (length(paquets_manquants) > 0) install.packages(paquets_manquants)

library(httr2)
library(sf)
library(dplyr)
library(writexl)

# --- Paramètres ---

projet   <- "france_isere"
base_url <- "https://app.clearance.teritorio.xyz"

cle    <- "amenity"     # clé OSM à modifier
valeur <- "restaurant"  # valeur OSM à modifier

# Zone géographique : c(sud, ouest, nord, est) ou NULL pour tout le projet
# Grenoble :      c(45.1, 5.6, 45.2, 5.8)
# Isère entière : c(44.68, 4.90, 45.47, 6.42)
bbox <- NULL

# --- Requête ---

if (!is.null(bbox)) {
  requete <- sprintf("nwr[%s=%s](%s);\nout body;", cle, valeur, paste(bbox, collapse = ","))
} else {
  requete <- sprintf("nwr[%s=%s];\nout body;", cle, valeur)
}

url <- sprintf("%s/api/0.1/projects/%s/overpasslike/interpreter", base_url, projet)

reponse <- request(url) |>
  req_body_form(data = requete) |>
  req_perform()

if (resp_status(reponse) != 200) {
  stop("Erreur API (", resp_status(reponse), ") : ", resp_body_string(reponse))
}

resultat <- resp_body_json(reponse, simplifyVector = FALSE)
elements <- resultat$elements

if (length(elements) == 0) stop("Aucun objet trouvé.")

# --- Conversion en objets sf ---

# Les nodes ont lat/lon directs.
# Les ways ont une liste de {lat, lon} ; polygone si le premier point = le dernier.
# Les relations n'ont pas de géométrie exploitable ici.
element_vers_geom <- function(e) {
  if (e$type == "node") {
    sf::st_point(c(e$lon, e$lat))
  } else if (e$type == "way" && length(e$geometry) > 0) {
    coords <- cbind(
      sapply(e$geometry, `[[`, "lon"),
      sapply(e$geometry, `[[`, "lat")
    )
    if (identical(coords[1, ], coords[nrow(coords), ])) {
      sf::st_polygon(list(coords))
    } else {
      sf::st_linestring(coords)
    }
  } else {
    sf::st_geometrycollection()
  }
}

geometries <- sf::st_sfc(lapply(elements, element_vers_geom), crs = 4326)

attributs <- bind_rows(lapply(elements, function(e) {
  base <- data.frame(id = e$id, type = e$type)
  if (!is.null(e$tags) && length(e$tags) > 0) {
    cbind(base, as.data.frame(e$tags))
  } else {
    base
  }
}))

donnees <- sf::st_sf(attributs, geometry = geometries, crs = 4326)

# --- Répartition par type de géométrie ---

types <- sf::st_geometry_type(donnees)

points         <- donnees[types == "POINT", ]
lignes         <- donnees[types %in% c("LINESTRING", "MULTILINESTRING"), ]
polygones      <- donnees[types == "POLYGON", ]
multipolygones <- donnees[types == "MULTIPOLYGON", ]

# --- Affichage ---

col_plot <- function(couche) if ("name" %in% names(couche)) "name" else NULL

if (nrow(points)         > 0) plot(points[col_plot(points)])
if (nrow(lignes)         > 0) plot(lignes[col_plot(lignes)])
if (nrow(polygones)      > 0) plot(polygones[col_plot(polygones)])
if (nrow(multipolygones) > 0) plot(multipolygones[col_plot(multipolygones)])

# --- Export Excel ---

couches <- list(
  points         = points,
  lignes         = lignes,
  polygones      = polygones,
  multipolygones = multipolygones
)

fichier_excel <- Filter(Negate(is.null), lapply(couches, function(couche) {
  if (nrow(couche) == 0) return(NULL)
  sf::st_drop_geometry(couche)
}))

write_xlsx(fichier_excel, paste0("resultat_", cle, "_", valeur, ".xlsx"))
