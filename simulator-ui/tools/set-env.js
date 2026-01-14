const fs = require('fs');
const path = require('path');

const targetPath = path.join(__dirname, '../public/env.js');
const apiUrl = process.env.API_URL || '';
const projectId = process.env.PROJECT_ID || '';

const envConfigFile = `window.ENV = {
  API_URL: "${apiUrl}",
  PROJECT_ID: "${projectId}",
};
`;

fs.writeFileSync(targetPath, envConfigFile);
console.log(`Output generated at ${targetPath} with API_URL=${apiUrl}, PROJECT_ID=${projectId}`);
