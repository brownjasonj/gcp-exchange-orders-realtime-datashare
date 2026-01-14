const express = require('express');
const path = require('path');
const fs = require('fs');
if (process.env.NODE_ENV !== 'production') {
    require('dotenv').config();
}
const app = express();

const PORT = parseInt(process.env.PORT) || 8080;
const DIST_PATH = path.join(__dirname, 'dist/ui/browser');

// Disable default index.html serving so we can inject config
// Serve dynamic environment config
app.use((req, res, next) => {
    console.log(`[DEBUG] Request: ${req.method} ${req.url}, requests path: ${req.path}`);
    next();
});

app.get('/env.js', (req, res) => {
    console.log('[DEBUG] Serving env.js');
    const apiUrl = process.env.API_URL || '';
    const projectId = process.env.PROJECT_ID || '';

    res.type('application/javascript');
    res.send(`window.ENV = { API_URL: "${apiUrl}", PROJECT_ID: "${projectId}" };`);
});

// Disable default index.html serving so we can handle SPA routing
console.log(`[DEBUG] Serving static files from: ${DIST_PATH}`);
if (fs.existsSync(DIST_PATH)) {
    console.log(`[DEBUG] DIST_PATH exists. Contents: ${fs.readdirSync(DIST_PATH)}`);
} else {
    console.error(`[DEBUG] DIST_PATH does not exist: ${DIST_PATH}`);
}

app.use(express.static(DIST_PATH, { index: false }));

// fs required at top

app.get('*', (req, res) => {
    console.log(`[DEBUG] Catch-all route hit for ${req.url}`);
    const indexPath = path.join(DIST_PATH, 'index.html');
    if (fs.existsSync(indexPath)) {
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
