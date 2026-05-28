# Kit de contenido — Reconstrucción de inemec.com

Material de referencia extraído del WordPress restaurado, para reconstruir el sitio
corporativo desde cero con el stack y la guía de diseño de Inemec. **No depende del
WordPress viejo** — una vez tengas este kit, el WordPress puede apagarse.

## Qué hay aquí

```
content-kit/
├── README.md                  # Este archivo
├── MAPA_DEL_SITIO.md          # Estructura de navegación (39 páginas + 3 posts)
├── MARCA.md                   # Logo, paleta de color, tipografía, redes, clientes
├── paginas/*.md               # Texto limpio de cada página (sin shortcodes)
├── posts/*.md                 # Entradas de blog
├── marca/                     # Logo principal + logos de clientes
│   ├── logo-inemec-horizontal.png
│   └── logos-cliente/
├── _media_referenciada.txt    # URLs de medios citados en el contenido
├── _full_content.json         # Export crudo (por si se necesita reprocesar)
└── _build_kit.py              # Script que generó este kit (re-ejecutable)
```

## Cómo usarlo para la reconstrucción

1. **Estructura**: `MAPA_DEL_SITIO.md` define qué páginas existen y su jerarquía.
   Es el esqueleto de la nueva información-arquitectura (puede simplificarse — hay
   páginas duplicadas/obsoletas que conviene consolidar).
2. **Contenido**: cada `.md` en `paginas/` trae el texto real, listo para volcar al
   nuevo sitio. El texto está limpio; revisar y actualizar donde haga falta.
3. **Marca**: `MARCA.md` da los colores y logos de arranque. Cruzar con la guía de
   diseño de frontend de Inemec.
4. **Medios**: las imágenes originales (445 MB, 5.037 archivos) siguen en el volumen
   del WordPress (`wordpress/wp-content/uploads/`) y en `originals/`. Copiar las que
   se reutilicen al nuevo proyecto; no todas valen la pena (muchas son variantes).
5. **Referencia visual**: el sitio sigue vivo en `https://site.inemec.com` para
   capturar cómo se ve cada sección.

## Notas sobre el contenido

- Las páginas se construyeron con WPBakery (page builder), así que el layout visual
  no se traslada — solo el texto. El diseño se rehace con la guía nueva.
- Algunas páginas salen casi vacías (`blog`, `talento-humano`, `news`): eran
  contenedores de bloques dinámicos o listados, sin texto propio.
- La política de tratamiento de datos (`tratamiento-datos.md`, 22 KB) es la más larga
  — documento legal completo, reutilizable casi tal cual.
- Hay PDFs de políticas en `wordpress/wp-content/uploads/2021/04/` (seguridad vial,
  anticorrupción, SGI, etc.) — documentos oficiales descargables.

## Inventario rápido

- **39 páginas** publicadas, **3 posts** de blog
- **~124.000 caracteres** de texto corporativo
- **5.037 archivos** de media (445 MB) en el WordPress
- **9 logos de clientes** + logo corporativo
- Paleta y redes sociales documentadas
