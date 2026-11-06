# Clearance — Overpass-like API

Clearance expose une API compatible [Overpass QL](https://wiki.openstreetmap.org/wiki/Overpass_API/Overpass_QL) exécutée directement sur sa base PostGIS.

---

## Endpoints

```
GET  /api/0.1/projects/{project}/overpasslike
GET  /api/0.1/projects/{project}/overpasslike/interpreter
POST /api/0.1/projects/{project}/overpasslike/interpreter
```

Le paramètre de requête s'appelle toujours **`data`**.

---

## Appeler l'API

> **Important :** toute requête doit se terminer par `out body;` ou `out center meta;`.
> Sans cette clause, la réponse contient un tableau de valeurs `null`.

### GET

```bash
curl "https://app.clearance.teritorio.xyz/api/0.1/projects/france_isere/overpasslike/interpreter?data=node[amenity=cafe](45.1,5.6,45.2,5.8);out%20body;"
```

### POST (recommandé pour les requêtes longues)

```bash
curl -X POST \
  "https://app.clearance.teritorio.xyz/api/0.1/projects/france_isere/overpasslike/interpreter" \
  --data-urlencode $'data=node[amenity=cafe](45.1,5.6,45.2,5.8);\nout body;'
```

---

## Syntaxe des requêtes (Overpass QL)

### Filtres sur les tags

```
node[amenity];                        // la clé existe (quelle que soit la valeur)
node[amenity=cafe];                   // égalité exacte
node[amenity!=cafe];                  // inégalité
node[name~"Town Hall"];               // valeur correspond à une regexp
node[name!~".*test.*"];               // valeur ne correspond PAS à la regexp
node[amenity=cafe][cuisine=french];   // plusieurs filtres combinés (ET)
```

### Bounding box

La bbox s'écrit **(sud, ouest, nord, est)** :

```
node[amenity=cafe](45.1, 5.6, 45.2, 5.8);
//                 lat_min,lon_min,lat_max,lon_max
```

### Types d'objets

| Type       | Contenu                       |
|------------|-------------------------------|
| `node`     | points OSM                    |
| `way`      | lignes et polygones OSM       |
| `relation` | relations OSM                 |
| `nwr`      | les trois types réunis        |
| `area`     | zones (polygones + relations) |

### Union

```
(
  node[amenity=school];
  way[amenity=school];
  relation[amenity=school];
);
out center meta;
```

### Ensembles nommés

Utile pour filtrer dans une zone définie par un objet OSM :

```
// Cafés dans une commune (relation OSM 123456)
area(id:3600123456)->.zone;
node[amenity=cafe](area.zone);
out body;
```

---

## Format de réponse

```json
{
  "version": 0.6,
  "generator": "Clearance",
  "osm3s": {
    "dataset": "france_isere",
    "copyright": "The data included in this document is from www.openstreetmap.org. The data is made available under ODbL."
  },
  "elements": [ ... ]
}
```

La structure de chaque élément dépend de son type et de la clause `out` utilisée.

### `out body` — node

```json
{
  "id": 313955011,
  "type": "node",
  "lat": 45.1884079,
  "lon": 5.7159042,
  "tags": { "amenity": "cafe", "name": "Le Gratin" },
  "geometry": { "type": "Point", "coordinates": [5.7159042, 45.1884079] }
}
```

### `out body` — way

```json
{
  "id": 50589769,
  "type": "way",
  "nodes": [643875819, 643875822, 643875814, 643875819],
  "bounds": { "minlat": 45.192, "minlon": 5.771, "maxlat": 45.193, "maxlon": 5.772 },
  "tags": { "amenity": "cafe", "name": "Le Factory Café" },
  "geometry": [
    { "lat": 45.1925011, "lon": 5.7710872 },
    { "lat": 45.1925049, "lon": 5.7712088 },
    { "lat": 45.1923904, "lon": 5.7712150 },
    { "lat": 45.1925011, "lon": 5.7710872 }
  ]
}
```

Un way dont le premier et le dernier nœud sont identiques forme un polygone fermé.

### `out body` — relation

```json
{
  "id": 54366,
  "type": "relation",
  "bounds": { "minlat": 45.252, "minlon": 5.707, "maxlat": 45.299, "maxlon": 5.754 },
  "tags": { "type": "multipolygon", "landuse": "forest" },
  "members": [
    { "ref": 28692397, "role": "inner", "type": "w" },
    { "ref": 164673953, "role": "outer", "type": "w" }
  ]
}
```

Les relations ne portent pas de géométrie, seulement la bounding box et les références des membres.

### `out center meta`

Ajoute `version`, `changeset`, `timestamp` et `uid` à chaque élément.
Pour les nodes, la structure est identique à `out body` avec ces champs en plus :

```json
{
  "id": 313955011,
  "type": "node",
  "lat": 45.1884079,
  "lon": 5.7159042,
  "uid": 23266880,
  "version": 13,
  "changeset": 181614383,
  "timestamp": "2026-04-21T08:09:16",
  "tags": { "amenity": "cafe", "name": "Business Class" }
}
```

Pour les ways, le tableau `geometry` est remplacé par un point `center` :

```json
{
  "id": 33233661,
  "type": "way",
  "uid": 5614084,
  "version": 7,
  "changeset": 169873886,
  "timestamp": "2025-08-02T17:39:34",
  "nodes": [377023702, 377023594, 377023617, 377023702],
  "center": { "lat": 45.1869049, "lon": 5.7303271 },
  "tags": { "amenity": "cafe", "name": "Isèreanybody" }
}
```

---

## Gestion des erreurs

| Code HTTP | Cause |
|-----------|-------|
| `200`     | Succès |
| `400`     | Syntaxe Overpass QL invalide |

En cas d'erreur `400`, le corps de la réponse est du HTML :

```html
<html><body>
<p><strong style="color:#FF0000">Error</strong>: Failed to parse query: ...</p>
</body></html>
```

---

## Exemples

### Restaurants dans une bounding box

```
node[amenity=restaurant](45.1,5.6,45.2,5.8);
out body;
```

### Nodes, ways et relations pour un tag donné

```
(
  node[leisure=park];
  way[leisure=park];
  relation[leisure=park];
);
out center meta;
```

### Objets dans une zone administrative

```
area(id:3600071154)->.isere;
(
  node[amenity=hospital](area.isere);
  way[amenity=hospital](area.isere);
);
out body;
```

---

## Limitations par rapport à l'API Overpass publique

Les fonctionnalités suivantes ne sont **pas supportées** :

- `out geom` / `out skel` / `out tags` — seuls `out body` et `out center meta` sont disponibles (`out body` retourne déjà les coordonnées et la géométrie complète)
- `around:<radius>` (filtre de proximité)
- `newer:<date>` (filtre temporel)
- `changed:<date>` / `user:<name>` (filtres par changeset)
- Récursion `>` / `<` (membres/parents)
- `is_in` (zone contenant un point)
- `timeline` / `attic` (données historiques)
