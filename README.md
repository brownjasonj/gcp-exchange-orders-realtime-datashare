<h1>GCP Native Real-Time Data with Delay Features</h1>

This repository demonstrates how to use GCP native services to provide real-time data and delays to that data as a steam, history data sets and shares data sets to data consumers without copying those data.  The problem is inspired by the need to provide real-time data to different exchange customers with a  variety of periodicities for different purposes.

<h4>Background</h4>
Securities exchanges generate a significant amount of real-time order data throughout the day  reflecting the continuous bid/offer price changes as a result of trading activities.  This data is consumed by different exchange customers with a  variety of periodicities for different purposes:

<h5>Real-Time (Ultra-Low latency)</h5>
Participants of an exchange have machines co-located in the exchanges data centres connected by short cables to limit pricing data latency and order submitting.  Pricing data is consumed directly via this dedicated link and primarily used by high velocity arbitrage trading algorithms.
<h5>Near-Time</h5>
Participants that are not located in the exchanges data centre, due to inhibitive cost for doing so, will receive the same pricing data but with a slight delay due with respect to the co-located participants.  Consumed data is used for algorithmic trading and providing updated pricing information for trader terminals and applications.
<h5>Daily Opening/Closing</h5>
The opening (or closing) bid/offer prices of a securities are used primarily for trading financial reporting and control purposes.
<h5>Historic pricing data</h5>
Historic data consists of all past ticking data from the exchange and made available as free or to paying customers.  Generally data that is older than 15 minutes is made available for free for anyone to consume.

<h1>Problem Statement</h1>
Creating a GCP cloud native solution for sharing historic data sets to any GCP customer.  The solution should satisfy the following set of requirements:

<ul>
<li>Accept a price data via a live streaming service</li>
<li>Provide two data sets with distinct access controls</li>
<li>All live data up to X years with the latest being no older than Y seconds</li>
<li>All live data up to X years with the latest no younger than Z minutes (Z assumed to be 15 minutes)</li>
<li>Enable producers of the data to define cost criteria for data consumption</li>
<li>Provide ability to bill GCP based consumers of the data via their project billing</li>
<li>Be the minimal storage and compute costs of any possible solution</li>
</ul>

<h4>Out of Scope</h4>
Compliance policy definition and implementation of data consumer access controls.
Integration of data consumption billing back to data producer billing systems

<h4>Open Questions</h4>
What are consumer data consumption patterns for these data sets?
What is the message data volume and frequency?


<h1>Evaluate Solutions</h1>
This repository provides a number of solutions to evaluate for the problem statement.  A data simulator and ui are provided to generate and publish data to a pub/sub topic.

## Pre-requisites

<ul>
<li>Google Cloud Platform (GCP) Project with Pub/Sub API enabled</li>
<li>Application Default Credentials (ADC) configured.</li>
</ul>

## How to use deploy

#### 1. Clone this repository

#### 2. cd into the terraform directory

#### 3. create a terraform.tfvars file.  you'll need to provide values for the following variables:

```
project_id       = <YOUR_PROJECT_ID>
network_vpc_name = <NAME_OF_PROJECT_VPC_TO_BE_USED>
subnetwork_name  = <NAME_OF_PROJECT_SUBNETWORK_TO_BE_USED>
pubsub_topic     = <NAME_OF_PUBSUB_TOPIC_TO_BE_CREATED>
region           = <REGION_FOR_REPLOYMENT>
```

#### 4. Deploy 
```bash
gcloud auth login
gcloud config set project <YOUR_PROJECT_ID>
gcloud auth application-default login
terraform init
terraform apply -auto-approve
```

### 5. Start the UI Proxy 
This tunnels traffic from `localhost:8080` to the remote private UI.
```bash
gcloud run services proxy simulator-ui --region=<REGION_FOR_REPLOYMENT> --port=8080
```