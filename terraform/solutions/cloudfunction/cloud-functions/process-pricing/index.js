const { BigQuery } = require('@google-cloud/bigquery');
const functions = require('@google-cloud/functions-framework');

const bigquery = new BigQuery();
const datasetId = process.env.DATASET_ID;
const tableId = process.env.TABLE_ID;
const projectId = process.env.PROJECT_ID;
const delaySeconds = parseInt(process.env.DELAY_IN_SECONDS || '0', 10);

functions.http('processPricingMessage', async (req, res) => {
  try {
    const message = req.body.message;
    if (!message || !message.data) {
      console.log('No message data received');
      res.status(400).send('Bad Request');
      return;
    }

    const base64Data = message.data;
    const jsonString = Buffer.from(base64Data, 'base64').toString();

    let messageData;
    try {
      messageData = JSON.parse(jsonString);
    } catch (e) {
      console.error('Failed to parse JSON body');
      res.status(200).send();
      return;
    }

    // Determine the reference timestamp.
    // Use the business timestamp from the payload if valid, otherwise Pub/Sub publishTime.
    let referenceTime;
    if (messageData.timestamp) {
      const parsed = new Date(messageData.timestamp);
      if (!isNaN(parsed.getTime())) {
        referenceTime = parsed;
      }
    }

    if (!referenceTime && message.publishTime) {
      referenceTime = new Date(message.publishTime);
    }

    if (!referenceTime) {
      console.error('No valid timestamp found in message or metadata');
      res.status(200).send(); // Ack to discard
      return;
    }

    const now = new Date();
    const diffSeconds = (now.getTime() - referenceTime.getTime()) / 1000;

    console.log(`Processing. RefTime: ${referenceTime.toISOString()}, Now: ${now.toISOString()}, Diff: ${diffSeconds}s, Delay: ${delaySeconds}s`);

    if (diffSeconds < delaySeconds) {
      const waitTime = delaySeconds - diffSeconds;
      console.log(`Message too fresh (Wait: ${waitTime}s). Nacking.`);
      // Nack (429/500) to trigger retry
      res.status(429).send(`Retry in ${waitTime}s`);
      return;
    }

    // Correct schema mismatch if needed? 
    // Requires exact match.
    await insertIntoBigQuery(messageData);
    console.log('Inserted into BigQuery');
    res.status(200).send('OK');

  } catch (err) {
    console.error('Error processing:', err);
    res.status(500).send('Internal Error');
  }
});

async function insertIntoBigQuery(row) {
  await bigquery
    .dataset(datasetId, { projectId })
    .table(tableId)
    .insert([row]);
}
