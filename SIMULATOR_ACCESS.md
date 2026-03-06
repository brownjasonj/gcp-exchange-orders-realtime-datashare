# Simulator Access Guide

The Simulator UI and Server are deployed to Google Cloud Run and are accessible directly via their public URLs. No proxies, tunnels, or extra gcloud commands are needed.

## Quick Start

1. **Deploy**:
   ```bash
   # From the terraform directory
   terraform apply -auto-approve
   ```

2. **Access the URL**:
   After the deployment completes, the URL of the UI will be displayed in the Terraform outputs as `simulator_ui_url`.

3. **Open in Browser**:
   Copy and paste that URL into your browser. 

## How it Works
The UI is configured via environment variables to connect directly to the backend shards in the cloud. It uses the `API_URLS` shard list to communicate with each simulator server directly. CORS headers are already implemented in the C++ backend to allow this direct cross-origin communication.

## Troubleshooting
If you experience connectivity issues:
* Ensure you are logged into GCP in your browser (if the services require authentication).
* Check the browser console (F12) for any blocking errors.
* Re-verify that the `API_URLS` in the UI logs match the real shard URLs.
