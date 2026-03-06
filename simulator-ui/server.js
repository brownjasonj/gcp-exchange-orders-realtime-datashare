const express = require('express');
const path = require('path');
const fs = require('fs');

if (process.env.NODE_ENV !== 'production') {
    require('dotenv').config();
}

const app = express();
const PORT = parseInt(process.env.PORT) || 8080;
const DIST_PATH = path.join(__dirname, 'dist/ui/browser');

// Log all requests for easier debugging in Cloud Run logs
app.use((req, res, next) => {
    console.log(`[DEBUG] ${new Date().toISOString()} Request: ${req.method} ${req.url}, original: ${req.originalUrl}, host: ${req.headers.host}`);

    // Trailing slash redirect for subpaths (essential for relative paths to work)
    if (req.url === '/' && req.originalUrl && !req.originalUrl.endsWith('/')) {
        console.log(`[DEBUG] Redirecting to add trailing slash: ${req.originalUrl}/`);
        return res.redirect(301, req.originalUrl + '/');
    }
    next();
});

// Dynamic environment config - handles both /env.js and /subpath/env.js
app.get(/env\.js$/, (req, res) => {
    console.log(`[DEBUG] Serving dynamic env.js for ${req.url}`);
    const apiUrlEnv = process.env.API_URLS || process.env.API_URL || '';
    const apiUrls = apiUrlEnv.split(',').filter(url => !!url);
    const projectId = process.env.PROJECT_ID || '';

    res.type('application/javascript');
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.send(`window.ENV = { API_URLS: ${JSON.stringify(apiUrls)}, PROJECT_ID: "${projectId}" };`);
});

// Serve static files relative to DIST_PATH
app.use(express.static(DIST_PATH, { index: false, maxAge: '1y' }));

// Robust subpath asset handler (e.g., /simulator-ui/main.js -> main.js)
// This ensures assets work even if the base href is missing or if the app is on a subpath.
app.use((req, res, next) => {
    const assetMatch = req.url.match(/\/([^/]+\.(js|css|png|jpg|jpeg|gif|ico|json|map|woff2?|ttf))$/);
    if (assetMatch) {
        const fileName = assetMatch[1];
        const filePath = path.join(DIST_PATH, fileName);
        if (fs.existsSync(filePath)) {
            console.log(`[DEBUG] Serving asset from subpath: ${req.url} -> ${fileName}`);
            return res.sendFile(filePath);
        }
    }
    next();
});

// SPA Catch-all
app.get('*', (req, res) => {
    console.log(`[DEBUG] Catch-all route hit for ${req.url}`);

    // Don't serve index.html for missing static files to avoid confusing the browser
    if (req.url.match(/\.(js|css|png|jpg|jpeg|gif|ico|json|map)$/)) {
        console.error(`[DEBUG] Missing static file: ${req.url}`);
        return res.status(404).send('File not found');
    }

    const indexPath = path.join(DIST_PATH, 'index.html');
    if (fs.existsSync(indexPath)) {
        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');

        // We use the index.html as-is with its <base href="./">
        // Relative paths work perfectly if the trailing slash redirect at the top is working.
        // This avoids the "broken base href" problem when proxied by GCF.
        res.sendFile(indexPath);
    } else {
        console.error(`[DEBUG] index.html not found at ${indexPath}`);
        res.status(404).send('index.html not found');
    }
});

// Export for GCF
exports.app = app;

if (require.main === module) {
    app.listen(PORT, () => {
        console.log(`UI Server running on port ${PORT}`);
    });
}

