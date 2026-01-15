const { Bigtable } = require('@google-cloud/bigtable');
const functions = require('@google-cloud/functions-framework');

const bigtable = new Bigtable();
const instanceId = process.env.BIGTABLE_INSTANCE_ID || 'paywall-instance';
const tableId = process.env.BIGTABLE_TABLE_ID || 'order_ticks_all';
const instance = bigtable.instance(instanceId);
const table = instance.table(tableId);


functions.cloudEvent('processPricing', async (cloudEvent) => {
  const base64name = cloudEvent.data.message.data;
  const dataString = Buffer.from(base64name, 'base64').toString();

  try {
    const json = JSON.parse(dataString);
    console.log('Processing message:', json);

    const rowKey = `${json.symbol}#${json.timestamp}`;

    const row = {
      key: rowKey,
      data: {
        data: {
          symbol: json.symbol,
          price: String(json.price),
          currency: json.currency,
          venue: json.venue,
          timestamp: json.timestamp,
          quantity: String(json.quantity),
          bidOffer: json.bidOffer,
          sequenceNumber: String(json.sequenceNumber)
        }
      }
    };

    await table.insert(row);
    console.log(`Successfully inserted row ${rowKey}`);
  } catch (error) {
    console.error('Error processing message:', error);
    // Rethrow to trigger retry if it's a transient error, or swallow if it's a parsing error?
    // Usually retrying is safe for Pub/Sub.
    throw error;
  }
});
