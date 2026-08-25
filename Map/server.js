const http = require("http");
const fs = require("fs");
const path = require("path");

const root = __dirname;
const port = Number(process.env.PORT || 8080);

const mimeTypes = {
  ".css": "text/css",
  ".geojson": "application/geo+json",
  ".html": "text/html",
  ".js": "text/javascript",
  ".json": "application/json",
  ".zip": "application/zip",
};

const server = http.createServer((request, response) => {
  const requestedPath = decodeURIComponent(new URL(request.url, `http://localhost:${port}`).pathname);
  const safePath = path.normalize(requestedPath).replace(/^(\.\.[/\\])+/, "");
  const filePath = path.join(root, safePath === "/" ? "index.html" : safePath);

  if (!filePath.startsWith(root)) {
    response.writeHead(403);
    response.end("Forbidden");
    return;
  }

  fs.stat(filePath, (statError, stats) => {
    if (statError || !stats.isFile()) {
      response.writeHead(404);
      response.end("Not found");
      return;
    }

    response.writeHead(200, {
      "Content-Type": mimeTypes[path.extname(filePath)] || "application/octet-stream",
      "Cache-Control": "no-store",
    });
    fs.createReadStream(filePath).pipe(response);
  });
});

server.listen(port, () => {
  console.log(`CAMFED map server running at http://localhost:${port}`);
});
