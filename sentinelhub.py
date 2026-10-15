# Install: pip install sentinelhub
from sentinelhub import SHConfig, SentinelHubRequest, DataCollection, MimeType, BBox, CRS

# Demo bounding box near Kajiado, Kenya
kajiado_bbox = BBox(bbox=[36.75, -1.88, 36.81, -1.82], crs=CRS.WGS84)

evalscript_ndvi = """
//VERSION=3
function setup() {
  return {
    input: ["B04", "B08"],
    output: { id: "default", bands: 1 }
  };
}
function evaluatePixel(sample) {
  let ndvi = (sample.B08 - sample.B04) / (sample.B08 + sample.B04);
  return [ndvi];
}
"""

print("Live satellite query ready for demo integration!")